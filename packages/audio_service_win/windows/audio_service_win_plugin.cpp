#include "audio_service_win_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Media.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <memory>
#include <sstream>
#include <iostream>
#include <fstream>  // std::ifstream
#include <vector>   // std::vector
#include <iterator> // std::istreambuf_iterator
#include <iomanip>
#include <future>
#include <mutex>
#include <queue>
#include <algorithm>

static winrt::Windows::Media::Playback::MediaPlayer mediaPlayer{nullptr};
static winrt::Windows::Media::SystemMediaTransportControls smtc{nullptr};
static winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater updater{nullptr};
static std::unique_ptr<flutter::MethodChannel<>> channel;
static std::string appId;
static winrt::event_token buttonToken{};
static std::vector<std::future<void>> artworkTasks;
static std::mutex buttonMutex;
static std::queue<std::string> pendingButtons;
static HWND callbackWindow = nullptr;
static flutter::PluginRegistrarWindows* pluginRegistrar = nullptr;
static int windowProcId = -1;
static constexpr UINT kMediaButtonMessage = WM_APP + 0x391;

namespace audio_service_win
{

  // static
  void AudioServiceWinPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {

    static bool plugin_already_registered = false;

    if (plugin_already_registered) {
      // Skip registration in subwindow
      return;
    }

    plugin_already_registered = true;
    pluginRegistrar = registrar;
    callbackWindow = registrar->GetView()->GetNativeWindow();
    callbackWindow = GetAncestor(callbackWindow, GA_ROOT);
    windowProcId = registrar->RegisterTopLevelWindowProcDelegate(
        [](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
          if (message != kMediaButtonMessage) return std::nullopt;
          std::queue<std::string> buttons;
          {
            std::lock_guard<std::mutex> lock(buttonMutex);
            buttons.swap(pendingButtons);
          }
          while (!buttons.empty()) {
            if (channel) channel->InvokeMethod("onSMTCButtonPressed",
                std::make_unique<flutter::EncodableValue>(buttons.front()));
            buttons.pop();
          }
          return 0;
        });

    channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "audio_service_win",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<AudioServiceWinPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  AudioServiceWinPlugin::AudioServiceWinPlugin() {}

  AudioServiceWinPlugin::~AudioServiceWinPlugin() {
    {
      std::lock_guard<std::mutex> lock(buttonMutex);
      callbackWindow = nullptr;
      pendingButtons = {};
    }
    if (smtc) {
      smtc.ButtonPressed(buttonToken);
      smtc.IsEnabled(false);
    }
    // Finish owned artwork work before releasing COM objects. Do not leave
    // static WinRT objects to destruct after the host's COM apartment exits.
    for (auto& task : artworkTasks) task.wait();
    artworkTasks.clear();
    updater = nullptr;
    smtc = nullptr;
    if (mediaPlayer) mediaPlayer.Close();
    mediaPlayer = nullptr;
    if (pluginRegistrar && windowProcId >= 0)
      pluginRegistrar->UnregisterTopLevelWindowProcDelegate(windowProcId);
    pluginRegistrar = nullptr;
    channel.reset();
  }

  // Function to setup System Media Transport Controls (SMTC)
  static void SetupSMTC()
  {
    if (mediaPlayer == nullptr)
    {
      mediaPlayer = winrt::Windows::Media::Playback::MediaPlayer();
      smtc = mediaPlayer.SystemMediaTransportControls();
      updater = smtc.DisplayUpdater();
      updater.AppMediaId(winrt::to_hstring(appId));

      smtc.IsPlayEnabled(true);
      smtc.IsPauseEnabled(true);
      smtc.IsNextEnabled(true);
      smtc.IsPreviousEnabled(true);
      smtc.IsEnabled(false); // Keep disabled until setMediaItem

      std::cout << "SMTC initialized with appid: " << appId << std::endl;

      buttonToken = smtc.ButtonPressed([](auto const &, winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs const &args)
                         {
                           std::string *method = new std::string;
                           switch (args.Button())
                           {
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Play:
                             *method = "play";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Pause:
                             *method = "pause";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Next:
                             *method = "next";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Previous:
                             *method = "previous";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Stop:
                             *method = "stop";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::FastForward:
                             *method = "fastForward";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Rewind:
                             *method = "rewind";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Record:
                             *method = "record";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::ChannelUp:
                             *method = "channelUp";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::ChannelDown:
                             *method = "channelDown";
                             break;
                           default:
                             *method = "other";
                             break;
                           }
                           // SMTC calls from a Windows worker thread. Deliver
                           // Flutter channel messages on the host window thread.
                           {
                             std::lock_guard<std::mutex> lock(buttonMutex);
                             if (callbackWindow) {
                               pendingButtons.push(*method);
                               PostMessage(callbackWindow, kMediaButtonMessage, 0, 0);
                             }
                           }
                           delete method; // Clean up the dynamically allocated string
                         });
    }
  }

} // namespace audio_service_win

namespace audio_service_win
{

  std::string UrlDecode(const std::string &encoded)
  {
    std::ostringstream result;
    for (size_t i = 0; i < encoded.size(); ++i)
    {
      if (encoded[i] == '%' && i + 2 < encoded.size())
      {
        int value;
        std::istringstream is(encoded.substr(i + 1, 2));
        if (is >> std::hex >> value)
        {
          result << static_cast<char>(value);
          i += 2;
        }
        else
        {
          result << encoded[i];
        }
      }
      else if (encoded[i] == '+')
      {
        result << ' ';
      }
      else
      {
        result << encoded[i];
      }
    }
    return result.str();
  }

  void AudioServiceWinPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {

    // Initialize System Media Transport Controls (SMTC) but do NOT enable or update notification yet
    if (method_call.method_name().compare("initializeSMTC") == 0)
    {
      std::cout << "Starting SMTC..." << std::endl;

      // Extract the appid argument from the method call
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("appid")) != arguments->end())
      {
        appId = std::get<std::string>(arguments->at(flutter::EncodableValue("appid")));

        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "appid is required");
      }
    }

    // Set/Update new Media metadata
    else if (method_call.method_name().compare("setMediaItem") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("title")) != arguments->end() &&
          arguments->find(flutter::EncodableValue("artist")) != arguments->end() &&
          arguments->find(flutter::EncodableValue("album")) != arguments->end())
      {
        std::string title;
        const auto &titleValue =
            arguments->at(flutter::EncodableValue("title"));
        if (!titleValue.IsNull() &&
            std::holds_alternative<std::string>(titleValue)) {
          title = std::get<std::string>(titleValue);
        }

        std::string artist;
        const auto &artistValue =
            arguments->at(flutter::EncodableValue("artist"));
        if (!artistValue.IsNull() &&
            std::holds_alternative<std::string>(artistValue)) {
          artist = std::get<std::string>(artistValue);
        }

        std::string album;
        const auto &albumValue =
            arguments->at(flutter::EncodableValue("album"));
        if (!albumValue.IsNull() &&
            std::holds_alternative<std::string>(albumValue)) {
          album = std::get<std::string>(albumValue);
        }

        // Ensure SMTC is initialized
        if (!smtc)
        {
          SetupSMTC();
        }

        std::string artUri;
        if (arguments->find(flutter::EncodableValue("artUri")) != arguments->end())
        {
          const auto &artUriValue = arguments->at(flutter::EncodableValue("artUri"));
          if (!artUriValue.IsNull() && std::holds_alternative<std::string>(artUriValue))
          {
            artUri = std::get<std::string>(artUriValue);
          }
        }

        if (updater)
        {
          smtc.IsEnabled(true);
          updater.ClearAll();
          updater.Type(winrt::Windows::Media::MediaPlaybackType::Music);
          updater.MusicProperties().Title(winrt::to_hstring(title));
          updater.MusicProperties().Artist(winrt::to_hstring(artist));
          updater.MusicProperties().AlbumTitle(winrt::to_hstring(album));

          if (!artUri.empty())
          {
            try
            {

              artworkTasks.erase(std::remove_if(artworkTasks.begin(), artworkTasks.end(),
                  [](auto& task) { return task.wait_for(std::chrono::seconds(0)) == std::future_status::ready; }),
                  artworkTasks.end());
              artworkTasks.push_back(std::async(std::launch::async, [artUri, artworkUpdater = updater]() mutable
                          {
              winrt::init_apartment(winrt::apartment_type::multi_threaded);
              try {
                  if (artUri.rfind("http://", 0) == 0 || artUri.rfind("https://", 0) == 0) {
                      winrt::Windows::Foundation::Uri uri(winrt::to_hstring(artUri));
                      auto thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(uri);
                      artworkUpdater.Thumbnail(thumbRef);
                  } else {
                      std::string localPath = artUri;
                      if (localPath.rfind("file://", 0) == 0) {
                          localPath = localPath.substr(8);
                          std::replace(localPath.begin(), localPath.end(), '/', '\\');
                      }
                      auto storageFile = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(winrt::to_hstring(UrlDecode(localPath))).get();
                      auto thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromFile(storageFile);
                      artworkUpdater.Thumbnail(thumbRef);
                  }
                  artworkUpdater.Update();
              } catch (const winrt::hresult_error& e) {
                  std::cerr << "Failed to set thumbnail: " << e.message().c_str() << std::endl;
              }
              artworkUpdater = nullptr;
              winrt::uninit_apartment();
              }));
            }
            catch (...)
            {
              // If thumbnail fails, continue without it
              std::cerr << "Failed to set thumbnail in Notification: " << artUri << std::endl;
            }
          }
          updater.Update();
        }
        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "title, artist, and album are required");
      }
    }

    // Update State
    else if (method_call.method_name().compare("updateState") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("state")) != arguments->end())
      {
        int32_t state = std::get<int32_t>(arguments->at(flutter::EncodableValue("state")));
        if (smtc)
        {
          smtc.IsEnabled(true);
          switch (state)
          {
          case 0: // Playing
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Playing);
            break;
          case 1: // Paused
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Paused);
            break;
          case 2: // Stopped
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Stopped);
            smtc.IsEnabled(false);
            updater.ClearAll();
            updater.Update();
            break;
          default:
            result->Error("InvalidArguments", "Invalid playback state");
            return;
          }
        }
        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "state is required");
      }
    }

    else
    {
      result->NotImplemented();
    }
  }

} // namespace audio_service_win

# Scoped overlay for flutter_inappwebview_windows 0.6.0. Never edit Pub's cache.
# Upstream issue: https://github.com/pichillilorenzo/flutter_inappwebview/issues/2733
# Release shared Composition resources during plugin teardown, before DLL unload.
set(_webview_target flutter_inappwebview_windows_plugin)
get_target_property(_webview_root ${_webview_target} SOURCE_DIR)
set(_manager_relative "in_app_webview/in_app_webview_manager.cpp")
set(_manager_original "${_webview_root}/${_manager_relative}")
file(SHA256 "${_manager_original}" _manager_hash)
if(NOT _manager_hash STREQUAL "eefc7b984c208696b3a3a34f99b0ddc11779fb7470009ebbabcfd274421d77ab")
  message(FATAL_ERROR "WebView manager source changed; review the scoped shutdown patch before building.")
endif()

file(READ "${_manager_original}" _manager_source)
string(REPLACE "namespace flutter_inappwebview_plugin" "#include <atomic>\nstatic std::atomic<unsigned> absorb_manager_instances{0};\n\nnamespace flutter_inappwebview_plugin" _manager_source "${_manager_source}")
string(REPLACE "    if (!rohelper_) {" "    ++absorb_manager_instances;\n    if (!rohelper_) {" _manager_source "${_manager_source}")
string(REPLACE "    plugin = nullptr;" [=[    plugin = nullptr;
    if (--absorb_manager_instances == 0) {
      // Dispose while the owning thread and Windows runtime are still alive.
      compositor_ = nullptr;
      graphics_context_.reset();
      dispatcher_queue_controller_ = nullptr;
      rohelper_.reset();
      valid_ = false;
    }]=] _manager_source "${_manager_source}")

set(_manager_generated "${CMAKE_CURRENT_BINARY_DIR}/patched_webview/in_app_webview_manager.cpp")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/patched_webview")
# configure_file avoids changing timestamps when the patch is unchanged.
file(WRITE "${_manager_generated}.in" "${_manager_source}")
configure_file("${_manager_generated}.in" "${_manager_generated}" COPYONLY)
get_target_property(_webview_sources ${_webview_target} SOURCES)
list(REMOVE_ITEM _webview_sources "${_manager_relative}" "${_manager_original}")
set_property(TARGET ${_webview_target} PROPERTY SOURCES "${_webview_sources}")
target_sources(${_webview_target} PRIVATE "${_manager_generated}")
target_include_directories(${_webview_target} PRIVATE "${_webview_root}/in_app_webview")

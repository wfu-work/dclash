// The IPv6 listener table needs winsock2.h, which has to come before the
// windows.h that proxy_plugin.h pulls in.
#include <winsock2.h>
#include <ws2ipdef.h>

#include "proxy_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <iphlpapi.h>
#include <stdlib.h>
#include <algorithm>
#include <functional>
#include <map>
#include <string>
#include <vector>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")
#pragma comment(lib, "iphlpapi")

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>

namespace
{

constexpr int kMinProxyPort = 1;
constexpr int kMaxProxyPort = 65535;
constexpr wchar_t kProxyServerPrefix[] = L"127.0.0.1:";

constexpr DWORD kProxyStateOptionCount = 5;

// WinINet's per-connection settings are independent for the default
// connection and for every RAS entry.  Keep all options that can affect
// whether a connection uses a proxy so stopping DClash restores the user's
// exact settings, including PAC and automatic discovery.
struct ConnectionProxyState
{
  std::optional<std::wstring> connection;
  DWORD flags = PROXY_TYPE_DIRECT;
  DWORD autodiscovery_flags = 0;
  std::wstring proxy_server;
  std::wstring proxy_bypass;
  std::wstring autoconfig_url;
};

struct ProxySnapshot
{
  std::vector<ConnectionProxyState> connections;
};

std::wstring Utf8ToWide(const std::string& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0)
  {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size);
  return result;
}

std::wstring BuildBypassList(const flutter::EncodableList& bypassDomain)
{
  std::wstring bypassList;
  for (const auto& domain : bypassDomain)
  {
    const auto& value = std::get<std::string>(domain);
    if (!bypassList.empty())
    {
      bypassList += L";";
    }
    bypassList += Utf8ToWide(value);
  }
  return bypassList;
}

bool IsStringList(const flutter::EncodableList& values)
{
  return std::all_of(
      values.begin(), values.end(), [](const auto& value)
      {
        return std::holds_alternative<std::string>(value);
      });
}

bool SetOptionsForConnection(
    INTERNET_PER_CONN_OPTION_LIST& list,
    LPTSTR connection)
{
  list.pszConnection = connection;
  return InternetSetOption(
      nullptr,
      INTERNET_OPTION_PER_CONNECTION_OPTION,
      &list,
      sizeof(list)) != FALSE;
}

bool ForEachConnection(const std::function<bool(LPTSTR)>& visit)
{
  bool success = visit(nullptr);

  DWORD size = 0;
  DWORD count = 0;
  auto ret = RasEnumEntries(nullptr, nullptr, nullptr, &size, &count);
  if (ret == ERROR_BUFFER_TOO_SMALL && count > 0)
  {
    std::vector<RASENTRYNAME> entries(count);
    for (auto& entry : entries)
    {
      entry.dwSize = sizeof(RASENTRYNAME);
    }
    ret = RasEnumEntries(nullptr, nullptr, entries.data(), &size, &count);
    if (ret == ERROR_SUCCESS)
    {
      for (DWORD i = 0; i < count; i++)
      {
        success = visit(entries[i].szEntryName) && success;
      }
    }
    else
    {
      success = false;
    }
  }
  else if (ret != ERROR_SUCCESS)
  {
    success = false;
  }

  return success;
}

bool ApplyOptionsToConnections(INTERNET_PER_CONN_OPTION_LIST& list)
{
  return ForEachConnection([&list](LPTSTR connection)
  {
    return SetOptionsForConnection(list, connection);
  });
}

bool NotifySettingsChanged()
{
  const bool changed = InternetSetOption(
      nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) != FALSE;
  const bool refreshed = InternetSetOption(
      nullptr, INTERNET_OPTION_REFRESH, nullptr, 0) != FALSE;
  return changed && refreshed;
}

bool QueryConnectionState(LPTSTR connection, ConnectionProxyState& state)
{
  std::vector<INTERNET_PER_CONN_OPTION> options(kProxyStateOptionCount);
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  options[4].dwOption = INTERNET_PER_CONN_AUTODISCOVERY_FLAGS;
  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  DWORD size = sizeof(list);
  const BOOL queried = InternetQueryOption(
      nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size);
  if (queried == FALSE)
  {
    for (const size_t index : {size_t(1), size_t(2), size_t(3)})
    {
      if (options[index].Value.pszValue != nullptr)
      {
        GlobalFree(options[index].Value.pszValue);
      }
    }
    return false;
  }

  state.connection = connection == nullptr
                         ? std::nullopt
                         : std::optional<std::wstring>(std::wstring(connection));
  state.flags = options[0].Value.dwValue;
  state.autodiscovery_flags = options[4].Value.dwValue;
  if (options[1].Value.pszValue != nullptr)
  {
    state.proxy_server = options[1].Value.pszValue;
  }
  if (options[2].Value.pszValue != nullptr)
  {
    state.proxy_bypass = options[2].Value.pszValue;
  }
  if (options[3].Value.pszValue != nullptr)
  {
    state.autoconfig_url = options[3].Value.pszValue;
  }

  // WinINet allocates strings returned by InternetQueryOption with
  // GlobalAlloc.  Free every returned string even when one of the values was
  // empty, otherwise repeated start/stop cycles leak the process heap.
  for (const size_t index : {size_t(1), size_t(2), size_t(3)})
  {
    if (options[index].Value.pszValue != nullptr)
    {
      GlobalFree(options[index].Value.pszValue);
    }
  }
  return true;
}

bool CaptureProxySnapshot(ProxySnapshot& snapshot)
{
  snapshot.connections.clear();
  return ForEachConnection(
      [&snapshot](LPTSTR connection)
      {
        ConnectionProxyState state;
        if (!QueryConnectionState(connection, state))
        {
          return false;
        }
        snapshot.connections.push_back(std::move(state));
        return true;
      });
}

bool RestoreConnectionState(const ConnectionProxyState& state)
{
  std::vector<INTERNET_PER_CONN_OPTION> options(kProxyStateOptionCount);
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = state.flags;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = const_cast<LPTSTR>(
      state.proxy_server.empty() ? L"" : state.proxy_server.c_str());
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = const_cast<LPTSTR>(
      state.proxy_bypass.empty() ? L"" : state.proxy_bypass.c_str());
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  options[3].Value.pszValue = const_cast<LPTSTR>(
      state.autoconfig_url.empty() ? L"" : state.autoconfig_url.c_str());
  options[4].dwOption = INTERNET_PER_CONN_AUTODISCOVERY_FLAGS;
  options[4].Value.dwValue = state.autodiscovery_flags;

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = state.connection.has_value()
                           ? const_cast<LPTSTR>(state.connection->c_str())
                           : nullptr;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();
  return InternetSetOption(
             nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
             sizeof(list)) != FALSE;
}

std::optional<int> ProxyPort(const std::wstring& server);

bool RestoreProxySnapshot(
    const ProxySnapshot& snapshot,
    const std::optional<int>& active_port)
{
  bool success = true;
  for (const auto& connection : snapshot.connections)
  {
    if (active_port.has_value())
    {
      ConnectionProxyState current;
      if (!QueryConnectionState(
              connection.connection.has_value()
                  ? const_cast<LPTSTR>(connection.connection->c_str())
                  : nullptr,
              current))
      {
        success = false;
        continue;
      }
      const auto current_port = ProxyPort(current.proxy_server);
      // The user may have changed the system proxy while DClash was running.
      // Do not overwrite that change when stopping or when the process is
      // being torn down.
      if ((current.flags & PROXY_TYPE_PROXY) == 0 || !current_port ||
          *current_port != *active_port)
      {
        continue;
      }
    }
    success = RestoreConnectionState(connection) && success;
  }
  return success;
}

bool startProxy(const int port, const flutter::EncodableList& bypassDomain)
{
  auto url = kProxyServerPrefix + std::to_wstring(port);
  auto bypassList = BuildBypassList(bypassDomain);
  std::vector<INTERNET_PER_CONN_OPTION> options(3);

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = url.data();

  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = bypassList.data();

  const bool optionsApplied = ApplyOptionsToConnections(list);
  const bool settingsNotified = NotifySettingsChanged();
  return optionsApplied && settingsNotified;
}

bool stopProxy(
    const ProxySnapshot& snapshot,
    const std::optional<int>& active_port = std::nullopt)
{
  const bool optionsApplied = RestoreProxySnapshot(snapshot, active_port);
  const bool settingsNotified = NotifySettingsChanged();
  return optionsApplied && settingsNotified;
}

std::optional<int> ProxyPort(const std::wstring& server)
{
  const std::wstring prefix = kProxyServerPrefix;
  if (server.size() <= prefix.size() || server.size() > prefix.size() + 5 ||
      server.compare(0, prefix.size(), prefix) != 0)
  {
    return std::nullopt;
  }
  int port = 0;
  for (size_t i = prefix.size(); i < server.size(); i++)
  {
    if (server[i] < L'0' || server[i] > L'9')
    {
      return std::nullopt;
    }
    port = port * 10 + (server[i] - L'0');
  }
  if (port < kMinProxyPort || port > kMaxProxyPort)
  {
    return std::nullopt;
  }
  return port;
}

template <typename Table>
bool TableHasPort(const std::vector<BYTE>& buffer, int port)
{
  const auto* table = reinterpret_cast<const Table*>(buffer.data());
  for (DWORD i = 0; i < table->dwNumEntries; i++)
  {
    const auto localPort =
        _byteswap_ushort(static_cast<USHORT>(table->table[i].dwLocalPort));
    if (localPort == port)
    {
      return true;
    }
  }
  return false;
}

std::optional<bool> HasTcpListener(ULONG family, int port)
{
  std::vector<BYTE> buffer;
  DWORD size = 0;
  DWORD result = ERROR_INSUFFICIENT_BUFFER;
  for (int attempt = 0; attempt < 3 && result == ERROR_INSUFFICIENT_BUFFER;
       attempt++)
  {
    buffer.resize(size);
    result = GetExtendedTcpTable(
        buffer.empty() ? nullptr : buffer.data(), &size, FALSE, family,
        TCP_TABLE_OWNER_PID_LISTENER, 0);
  }
  if (result != NO_ERROR)
  {
    return std::nullopt;
  }
  return family == AF_INET
             ? TableHasPort<MIB_TCPTABLE_OWNER_PID>(buffer, port)
             : TableHasPort<MIB_TCP6TABLE_OWNER_PID>(buffer, port);
}

// A lookup that fails counts as listening, so a live proxy is never cleared.
bool IsPortListening(int port)
{
  for (const ULONG family : {static_cast<ULONG>(AF_INET),
                             static_cast<ULONG>(AF_INET6)})
  {
    if (HasTcpListener(family, port).value_or(true))
    {
      return true;
    }
  }
  return false;
}

// taskkill /f returns once TerminateProcess has been issued, which is before
// the killed Core has released its listening socket.
bool IsPortReleased(int port)
{
  for (int attempt = 0; attempt < 20; attempt++)
  {
    if (!IsPortListening(port))
    {
      return true;
    }
    Sleep(100);
  }
  return false;
}

bool ClearStaleProxyForConnection(
    LPTSTR connection,
    int target_port,
    std::map<int, bool>& releasedPorts)
{
  std::vector<INTERNET_PER_CONN_OPTION> options(2);
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  DWORD size = sizeof(list);
  if (InternetQueryOption(
          nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size) ==
      FALSE)
  {
    if (options[1].Value.pszValue != nullptr)
    {
      GlobalFree(options[1].Value.pszValue);
    }
    return false;
  }
  const DWORD flags = options[0].Value.dwValue;
  std::wstring server;
  if (options[1].Value.pszValue != nullptr)
  {
    server = options[1].Value.pszValue;
    GlobalFree(options[1].Value.pszValue);
  }

  const auto port = ProxyPort(server);
  if ((flags & PROXY_TYPE_PROXY) == 0 || !port || *port != target_port)
  {
    return true;
  }
  auto [released, unchecked] = releasedPorts.try_emplace(*port, false);
  if (unchecked)
  {
    released->second = IsPortReleased(*port);
  }
  if (!released->second)
  {
    return true;
  }
  INTERNET_PER_CONN_OPTION option = {};
  option.dwOption = INTERNET_PER_CONN_FLAGS;
  option.Value.dwValue = (flags & ~PROXY_TYPE_PROXY) | PROXY_TYPE_DIRECT;
  list.dwOptionCount = 1;
  list.pOptions = &option;
  return SetOptionsForConnection(list, connection);
}

}  // namespace

namespace proxy
{

struct ProxyState
{
  std::optional<ProxySnapshot> snapshot;
  std::optional<int> active_port;
};

  bool ClearStaleProxy(int port)
  {
    if (port < kMinProxyPort || port > kMaxProxyPort)
    {
      return false;
    }
    std::map<int, bool> releasedPorts;
    const bool cleared = ForEachConnection(
        [port, &releasedPorts](LPTSTR connection)
        {
          return ClearStaleProxyForConnection(connection, port, releasedPorts);
        });
    const bool settingsNotified = NotifySettingsChanged();
    return cleared && settingsNotified;
  }

  // static
  void ProxyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "proxy",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<ProxyPlugin>(registrar);

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  ProxyPlugin::ProxyPlugin() : state_(std::make_unique<ProxyState>()) {}

  ProxyPlugin::ProxyPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar), state_(std::make_unique<ProxyState>())
  {
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND window, UINT message, WPARAM wparam, LPARAM lparam)
        {
          return HandleWindowProc(window, message, wparam, lparam);
        });
  }

  ProxyPlugin::~ProxyPlugin()
  {
    if (state_ != nullptr && state_->snapshot.has_value())
    {
      // The normal Dart shutdown path calls StopProxy, but restoring here
      // also covers engine teardown and plugin destruction after an error.
      if (stopProxy(*state_->snapshot, state_->active_port))
      {
        state_->snapshot.reset();
        state_->active_port.reset();
      }
    }
    if (registrar_ != nullptr)
    {
      registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    }
  }

  bool ProxyPlugin::IsSessionEnding(UINT message, WPARAM wparam)
  {
    return message == WM_ENDSESSION && wparam != FALSE;
  }

  // Shutting Windows down kills the process without running the Dart exit path,
  // so the setting survives into a boot with nothing listening behind it.
  std::optional<LRESULT> ProxyPlugin::HandleWindowProc(
      HWND window, UINT message, WPARAM wparam, LPARAM lparam)
  {
    if (state_ != nullptr && state_->snapshot.has_value() &&
        IsSessionEnding(message, wparam))
    {
      if (stopProxy(*state_->snapshot, state_->active_port))
      {
        state_->snapshot.reset();
        state_->active_port.reset();
      }
    }
    return std::nullopt;
  }

  void ProxyPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name() == "StopProxy")
    {
      const bool stopped = state_ == nullptr || !state_->snapshot.has_value()
                               ? true
                               : stopProxy(*state_->snapshot,
                                           state_->active_port);
      if (stopped && state_ != nullptr)
      {
        state_->snapshot.reset();
        state_->active_port.reset();
      }
      result->Success(stopped);
    }
    else if (method_call.method_name() == "RecoverStaleProxy")
    {
      auto *arguments =
          std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments == nullptr)
      {
        result->Error("bad_args", "RecoverStaleProxy requires argument map");
        return;
      }
      auto portIt = arguments->find(flutter::EncodableValue("port"));
      auto *port = portIt == arguments->end()
                       ? nullptr
                       : std::get_if<int>(&portIt->second);
      if (port == nullptr || *port < kMinProxyPort || *port > kMaxProxyPort)
      {
        result->Error(
            "bad_args", "RecoverStaleProxy port must be between 1 and 65535");
        return;
      }
      result->Success(ClearStaleProxy(*port));
    }
    else if (method_call.method_name() == "StartProxy")
    {
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments == nullptr)
      {
        result->Error("bad_args", "StartProxy requires argument map");
        return;
      }
      auto portIt = arguments->find(flutter::EncodableValue("port"));
      auto bypassDomainIt = arguments->find(flutter::EncodableValue("bypassDomain"));
      if (portIt == arguments->end() || bypassDomainIt == arguments->end())
      {
        result->Error("bad_args", "StartProxy requires port and bypassDomain");
        return;
      }
      auto *port = std::get_if<int>(&portIt->second);
      auto *bypassDomain = std::get_if<flutter::EncodableList>(&bypassDomainIt->second);
      if (port == nullptr || bypassDomain == nullptr)
      {
        result->Error("bad_args", "StartProxy argument types are invalid");
        return;
      }
      if (*port < kMinProxyPort || *port > kMaxProxyPort)
      {
        result->Error("bad_args", "StartProxy port must be between 1 and 65535");
        return;
      }
      if (!IsStringList(*bypassDomain))
      {
        result->Error(
            "bad_args", "StartProxy bypassDomain must contain only strings");
        return;
      }
      if (state_ == nullptr)
      {
        result->Success(false);
        return;
      }
      // A live session owns the snapshot and the port that was applied.  A
      // second start on a different port cannot be rolled back safely: the
      // original proxy would remain active while the snapshot could be
      // discarded.  Require callers to stop the current session first.
      if (state_->snapshot.has_value() && state_->active_port.has_value() &&
          *state_->active_port != *port)
      {
        result->Success(false);
        return;
      }
      if (!state_->snapshot.has_value())
      {
        ProxySnapshot snapshot;
        if (!CaptureProxySnapshot(snapshot))
        {
          result->Success(false);
          return;
        }
        state_->snapshot = std::move(snapshot);
      }

      // A start that reports failure can still have written the setting. Roll
      // back to the captured state so a failed enable never leaves a proxy
      // pointing at a port the app did not successfully claim.
      // Record the target before writing so a partial start can be rolled back
      // only where WinINet still points at this invocation's loopback port.
      state_->active_port = *port;
      const bool started = startProxy(*port, *bypassDomain);
      if (!started)
      {
        if (stopProxy(*state_->snapshot, state_->active_port))
        {
          state_->snapshot.reset();
          state_->active_port.reset();
        }
      }
      result->Success(started);
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy

#!/usr/bin/env bash

echo "Script starting..."

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# GitHub repository base URL
GITHUB_BASE="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main"

# Logging functions
log_message() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

download_file() {
  local url="$1"
  local output="$2"
  
  if command -v curl &> /dev/null; then
    curl -s "$url" -o "$output"
  elif command -v wget &> /dev/null; then
    wget -q "$url" -O "$output"
  else
    log_error "Neither curl nor wget is installed. Please install one of them."
    return 1
  fi
  
  if [ ! -s "$output" ]; then
    log_error "Failed to download $url"
    return 1
  fi
  
  return 0
}

locate_brave_files() {
  log_message "Locating Brave browser..."
  
  if command -v flatpak &> /dev/null; then
    BRAVE_FLATPAK=$(flatpak list --app | grep com.brave.Browser)
    if [[ -n "${BRAVE_FLATPAK}" ]]; then
      log_message "Flatpak Brave installation detected"
      BRAVE_EXEC="flatpak run com.brave.Browser"
      PREFERENCES_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"
      POLICY_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/policies/managed"
      IS_FLATPAK=true
    fi
  fi

  if [[ -z "${BRAVE_EXEC}" ]]; then
    BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable)"
    if [[ -z "${BRAVE_EXEC}" ]]; then
      log_message "Brave browser not found. Would you like to install it? (y/n)"
      read -p "> " install_choice
      if [[ "${install_choice}" =~ ^[Yy]$ ]]; then
        install_brave_variant "stable"
        BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable)"
        if [[ -z "${BRAVE_EXEC}" ]]; then
          log_error "Installation failed or Brave not found in PATH"
          exit 1
        fi
      else
        log_error "Brave browser is required for this script"
        exit 1
      fi
    fi
    
    PREFERENCES_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/Default"
    POLICY_DIR="/etc/brave/policies/managed"
    IS_FLATPAK=false
  fi

  mkdir -p "${POLICY_DIR}"
  mkdir -p "/usr/share/brave"
  mkdir -p "${PREFERENCES_DIR}"

  BRAVE_PREFS="${PREFERENCES_DIR}/Preferences"

  log_message "Brave executable: ${BRAVE_EXEC}"
  log_message "Policy directory: ${POLICY_DIR}"
  log_message "Preferences directory: ${PREFERENCES_DIR}"
}

install_brave_variant() {
  local variant="$1"
  local script_url=""
  
  case "$variant" in
    "stable")
      script_url="${GITHUB_BASE}/brave_install/install_brave_stable.sh"
      ;;
    "beta")
      script_url="${GITHUB_BASE}/brave_install/install_brave_beta.sh"
      ;;
    "nightly")
      script_url="${GITHUB_BASE}/brave_install/install_brave_nightly.sh"
      ;;
    *)
      log_error "Invalid Brave variant: $variant"
      return 1
      ;;
  esac
  
  local temp_script=$(mktemp)
  if download_file "$script_url" "$temp_script"; then
    chmod +x "$temp_script"
    "$temp_script"
    local result=$?
    rm "$temp_script"
    
    if command -v brave-browser &> /dev/null || command -v brave &> /dev/null || command -v brave-browser-beta &> /dev/null || command -v brave-browser-nightly &> /dev/null; then
      log_message "Brave Browser (${variant}) installed successfully."
      return 0
    fi
    
    if [[ "$variant" == "stable" ]]; then
      log_message "Standard installation methods failed. Trying Brave's official install script..."
      curl -fsS https://dl.brave.com/install.sh | sh
      if command -v brave-browser &> /dev/null || command -v brave &> /dev/null; then
        log_message "Brave Browser (stable) installed successfully using official script."
        return 0
      else
        log_error "All installation methods failed."
        return 1
      fi
    else
      log_error "Installation of Brave Browser (${variant}) failed. No fallback available for non-stable variants."
      return 1
    fi
  else
    log_error "Failed to download installation script for ${variant}"
    return 1
  fi
}

create_brave_wrapper() {
  log_message "Creating Brave wrapper script..."
  
  local wrapper_path="/usr/local/bin/brave-debloat-wrapper"
  
  cat > "$wrapper_path" << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_message() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }

BRAVE_EXEC=$(command -v brave-browser || command -v brave || command -v brave-browser-stable)
EXTENSIONS_DIR="/usr/share/brave/extensions"
THEMES_DIR="/usr/share/brave/themes"
DASHBOARD_DIR="/usr/share/brave/dashboard-extension"

# Load only non-default extensions
EXTENSION_ARGS=""
if [[ -d "$DASHBOARD_DIR" ]]; then
  EXTENSION_ARGS="--load-extension=${DASHBOARD_DIR}"
  log_message "Dashboard Customizer is installed"
fi
if [[ -d "$EXTENSIONS_DIR" ]]; then
  for ext_dir in "$EXTENSIONS_DIR"/*; do
    if [[ -d "$ext_dir" && "$ext_dir" != "$DASHBOARD_DIR" && ! "$(basename "$ext_dir")" =~ ^(cjpalhdlnbpafiamejdnhcphjbkeiagm|eimadpbcbfnmbkopoojfekhnkhdbieeh)$ ]]; then
      EXTENSION_ARGS="${EXTENSION_ARGS:+$EXTENSION_ARGS,}${ext_dir}"
    fi
  done
fi
if [[ -d "$THEMES_DIR" ]]; then
  for theme_dir in "$THEMES_DIR"/*; do
    if [[ -d "$theme_dir" && ! "$(basename "$theme_dir")" =~ ^(annfbnbieaamhaimclajlajpijgkdblo)$ ]]; then
      EXTENSION_ARGS="${EXTENSION_ARGS:+$EXTENSION_ARGS,}${theme_dir}"
    fi
  done
fi

# Check for dark mode flag
DARK_MODE_FLAG="/tmp/brave_debloat_dark_mode"
DARK_MODE=""
if [[ -f "$DARK_MODE_FLAG" ]]; then
  DARK_MODE="--force-dark-mode"
fi

log_message "Launching Brave with managed extensions"
exec "$BRAVE_EXEC" $EXTENSION_ARGS --homepage=chrome://newtab $DARK_MODE "$@"
EOF

  chmod +x "$wrapper_path"
  log_message "Brave wrapper script created at $wrapper_path"
  return 0
}

apply_policy() {
  local policy_name="$1"
  local policy_file="${POLICY_DIR}/${policy_name}.json"
  
  log_message "Applying ${policy_name} policy..."
  if download_file "${GITHUB_BASE}/policies/${policy_name}.json" "$policy_file"; then
    chmod 644 "$policy_file"
    log_message "${policy_name} policy applied successfully"
    return 0
  else
    log_error "Failed to apply ${policy_name} policy"
    return 1
  fi
}

toggle_policy() {
  local policy_name="$1"
  local policy_file="${POLICY_DIR}/${policy_name}.json"
  local feature_name="$2"
  
  if [[ -f "$policy_file" ]]; then
    log_message "${feature_name} is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "${feature_name} disabled"
    else
      log_message "${feature_name} remains enabled"
    fi
  else
    apply_policy "$policy_name"
    log_message "${feature_name} enabled"
  fi
}

create_desktop_entry() {
  log_message "Creating desktop entry for Brave Debloat..."
  
  create_brave_wrapper
  
  local icon_path="brave-browser"
  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  
  cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=Brave Debloat
GenericName=Web Browser
Comment=Debloated and optimized Brave browser
Exec=/usr/local/bin/brave-debloat-wrapper %U
Icon=${icon_path}
Type=Application
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=/usr/local/bin/brave-debloat-wrapper

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=/usr/local/bin/brave-debloat-wrapper --incognito
EOF

  chmod 644 "$desktop_file"
  
  if command -v update-desktop-database &> /dev/null; then
    update-desktop-database
  fi
  
  if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor
  fi
  
  log_message "Desktop entry created successfully with wrapper script"
  return 0
}

install_extension_from_crx() {
  local ext_id="$1"
  local ext_name="$2"
  local crx_url="$3"
  local ext_dir="/usr/share/brave/extensions/${ext_id}"
  local crx_path="/usr/share/brave/extensions/${ext_id}.crx"
  
  if [[ -d "$ext_dir" ]]; then
    if [[ ! -f "$ext_dir/_metadata" ]]; then
      log_message "${ext_name} is already installed"
      return 0
    else
      log_message "Cleaning up old ${ext_name} install..."
      rm -rf "$ext_dir"
    fi
  fi
  
  log_message "Installing ${ext_name}..."
  mkdir -p "/usr/share/brave/extensions"
  if download_file "$crx_url" "$crx_path"; then
    chmod 644 "$crx_path"
    mkdir -p "$ext_dir"
    unzip -o "$crx_path" -d "$ext_dir" >/dev/null 2>&1
    rm -rf "$ext_dir/_metadata"  # Fix _metadata error
    update_extension_settings "$ext_id" "$ext_name"
    log_message "${ext_name} installed successfully"
    return 0
  else
    log_error "Failed to download ${ext_name}"
    return 1
  fi
}

update_extension_settings() {
  local ext_id="$1"
  local ext_name="$2"
  local policy_file="${POLICY_DIR}/extension_settings.json"
  
  if [[ -f "$policy_file" ]]; then
    local temp_file="${policy_file}.tmp"
    jq ".ExtensionSettings[\"${ext_id}\"] = {\"installation_mode\": \"normal_installed\", \"update_url\": \"https://clients2.google.com/service/update2/crx\"}" "$policy_file" > "$temp_file"
    mv "$temp_file" "$policy_file"
  else
    cat > "$policy_file" << EOF
{
  "ExtensionSettings": {
    "${ext_id}": {
      "installation_mode": "normal_installed",
      "update_url": "https://clients2.google.com/service/update2/crx"
    }
  }
}
EOF
  fi
  
  chmod 644 "$policy_file"
}

install_theme() {
  local theme_id="$1"
  local theme_name="$2"
  local crx_url="$3"
  
  log_message "Installing theme: ${theme_name}..."
  
  if [[ "$theme_id" == "brave_dark_mode" ]]; then
    set_brave_dark_mode
    return 0
  fi
  
  local theme_dir="/usr/share/brave/themes/${theme_id}"
  if [[ -d "$theme_dir" ]]; then
    if [[ ! -f "$theme_dir/_metadata" ]]; then
      log_message "Theme ${theme_name} is already installed"
      return 0
    else
      log_message "Cleaning up old ${theme_name} install..."
      rm -rf "$theme_dir"
    fi
  fi
  
  if [[ -f "${POLICY_DIR}/dark_mode.json" ]]; then
    log_message "Dark mode is currently enabled. Disabling for theme compatibility..."
    rm -f "${POLICY_DIR}/dark_mode.json"
    rm -f "/tmp/brave_debloat_dark_mode"
  fi
  
  mkdir -p "/usr/share/brave/themes"
  local crx_path="/usr/share/brave/themes/${theme_id}.crx"
  if download_file "$crx_url" "$crx_path"; then
    chmod 644 "$crx_path"
    mkdir -p "$theme_dir"
    unzip -o "$crx_path" -d "$theme_dir" >/dev/null 2>&1
    rm -rf "$theme_dir/_metadata"  # Fix _metadata error
    update_extension_settings "$theme_id" "$theme_name"
    update_desktop_with_extensions
    log_message "Theme ${theme_name} activated"
    return 0
  else
    log_error "Failed to download theme ${theme_name}"
    return 1
  fi
  
  pkill -9 -f "brave.*" || true
  log_message "Brave restarted to apply theme"
}

select_theme() {
  log_message "Loading available themes..."
  
  local temp_file=$(mktemp)
  if ! download_file "${GITHUB_BASE}/policies/consolidated_extensions.json" "$temp_file"; then
    log_error "Failed to download theme data"
    rm "$temp_file"
    return 1
  fi

  local theme_count=$(jq '.categories.themes | length' "$temp_file")
  if [ "$theme_count" -eq 0 ]; then
    log_error "No themes found in the extensions data"
    rm "$temp_file"
    return 1
  fi

  echo -e "\n=== Available Themes ==="
  local i=1
  declare -A theme_map
  
  while read -r id && read -r name && read -r description && read -r crx_url; do
    printf "%2d. %-35s - %s\n" "$i" "$name" "$description"
    theme_map["$i"]="$id|$name|$crx_url"
    ((i++))
  done < <(jq -r '.categories.themes[] | (.id, .name, .description, .crx_url)' "$temp_file")
  
  echo -e "\nSelect a theme to install (1-$((i-1))): "
  read theme_choice
  
  if [[ -n "${theme_map[$theme_choice]}" ]]; then
    IFS='|' read -r id name crx_url <<< "${theme_map[$theme_choice]}"
    install_theme "$id" "$name" "$crx_url"
  else
    log_error "Invalid selection: $theme_choice"
  fi
  
  rm "$temp_file"
}

modify_dashboard_preferences() {
  local preferences_file="${BRAVE_PREFS}"
  
  if [[ -f "${preferences_file}" ]] && jq -e '.brave.new_tab_page.show_clock == true and .brave.new_tab_page.show_shortcuts == false' "${preferences_file}" >/dev/null 2>&1; then
    log_message "Dashboard is already customized"
    return 0
  fi
  
  mkdir -p "${PREFERENCES_DIR}"
  
  if [[ ! -f "${preferences_file}" ]]; then
    echo "{}" > "${preferences_file}"
    chmod 644 "${preferences_file}"
  fi
  
  local temp_file="${preferences_file}.tmp"
  jq '.brave = (.brave // {}) | 
      .brave.stats = (.brave.stats // {}) | 
      .brave.stats.enabled = false | 
      .brave.today = (.brave.today // {}) | 
      .brave.today.should_show_brave_today_widget = false | 
      .brave.new_tab_page = (.brave.new_tab_page // {}) | 
      .brave.new_tab_page.show_clock = true | 
      .brave.new_tab_page.show_search_widget = false |
      .brave.new_tab_page.show_branded_background_image = false |
      .brave.new_tab_page.show_cards = false |
      .brave.new_tab_page.show_background_image = false |
      .brave.new_tab_page.show_stats = false |
      .brave.new_tab_page.show_shortcuts = false' "${preferences_file}" > "${temp_file}"
  mv "${temp_file}" "${preferences_file}"
  chmod 644 "${preferences_file}"
  log_message "Modified dashboard preferences - removed all widgets, added clock"
}

install_brave_and_optimize() {
  log_message "Installing Brave and applying optimizations..."
  install_brave_variant "stable"
  apply_default_optimizations
}

set_search_engine() {
  while true; do
    clear
    echo "=== Search Engine Selection ==="
    echo "1. Brave Search (Privacy focused but collects data)"
    echo "2. DuckDuckGo (Privacy focused but collects data)"
    echo "3. SearXNG (Recommended but only if self-hosted)"
    echo "4. Whoogle (Recommended but only if self-hosted)"
    echo "5. Yandex (enjoy russian botnet)"
    echo "6. Kagi (excellent engine, but a paid service)"
    echo "7. Google (welcome to the botnet)"
    echo "8. Bing (enjoy your AIDs)"
    echo "9. Back to main menu"
    
    read -p "Enter your choice [1-9]: " search_choice
    local policy_file="${POLICY_DIR}/search_provider.json"
    
    case ${search_choice} in
      1)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Brave",
  "DefaultSearchProviderSearchURL": "https://search.brave.com/search?q={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "brave", "name": "Brave", "search_url": "https://search.brave.com/search?q={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to Brave Search"
        break
        ;;
      2)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "DuckDuckGo",
  "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "ddg", "name": "DuckDuckGo", "search_url": "https://duckduckgo.com/?q={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to DuckDuckGo"
        break
        ;;
      3)
        read -p "Enter your SearXNG instance URL (e.g., https://searxng.example.com): " searx_url
        if [[ "${searx_url}" =~ ^https?:// ]]; then
          cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "SearXNG",
  "DefaultSearchProviderSearchURL": "${searx_url}/search?q={searchTerms}"
}
EOF
          chmod 644 "${policy_file}"
          jq ".default_search_provider_data = {\"keyword\": \"searxng\", \"name\": \"SearXNG\", \"search_url\": \"${searx_url}/search?q={searchTerms}\"}" "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
          mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
          chmod 644 "${BRAVE_PREFS}"
          log_message "Search engine set to SearXNG"
          break
        else
          log_error "Invalid URL format"
          sleep 2
        fi
        ;;
      4)
        read -p "Enter your Whoogle instance URL (e.g., https://whoogle.example.com): " whoogle_url
        if [[ "${whoogle_url}" =~ ^https?:// ]]; then
          cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Whoogle",
  "DefaultSearchProviderSearchURL": "${whoogle_url}/search?q={searchTerms}"
}
EOF
          chmod 644 "${policy_file}"
          jq ".default_search_provider_data = {\"keyword\": \"whoogle\", \"name\": \"Whoogle\", \"search_url\": \"${whoogle_url}/search?q={searchTerms}\"}" "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
          mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
          chmod 644 "${BRAVE_PREFS}"
          log_message "Search engine set to Whoogle"
          break
        else
          log_error "Invalid URL format"
          sleep 2
        fi
        ;;
      5)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Yandex",
  "DefaultSearchProviderSearchURL": "https://yandex.com/search/?text={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "yandex", "name": "Yandex", "search_url": "https://yandex.com/search/?text={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to Yandex"
        break
        ;;
      6)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Kagi",
  "DefaultSearchProviderSearchURL": "https://kagi.com/search?q={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "kagi", "name": "Kagi", "search_url": "https://kagi.com/search?q={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to Kagi"
        break
        ;;
      7)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "google", "name": "Google", "search_url": "https://www.google.com/search?q={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to Google"
        break
        ;;
      8)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Bing",
  "DefaultSearchProviderSearchURL": "https://www.bing.com/search?q={searchTerms}"
}
EOF
        chmod 644 "${policy_file}"
        jq '.default_search_provider_data = {"keyword": "bing", "name": "Bing", "search_url": "https://www.bing.com/search?q={searchTerms}"}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        chmod 644 "${BRAVE_PREFS}"
        log_message "Search engine set to Bing"
        break
        ;;
      9)
        log_message "Returning to main menu"
        return
        ;;
      *)
        log_error "Invalid option"
        sleep 2
        ;;
    esac
  done
  pkill -9 -f "brave.*" || true
  local secure_prefs="${HOME}/.config/BraveSoftware/Brave-Browser/Default/Secure Preferences"
  if [[ -f "$secure_prefs" ]]; then
    jq 'del(.extensions.settings[] | select(.search_provider)) | del(.omnibox)' "$secure_prefs" > "$secure_prefs.tmp"
    mv "$secure_prefs.tmp" "$secure_prefs"
    chmod 644 "$secure_prefs"
  fi
  rm -rf "${HOME}/.cache/BraveSoftware/Brave-Browser/*"
  log_message "All Brave processes killed and caches cleared to enforce new search engine"
}

apply_default_optimizations() {
  log_message "Applying default optimizations..."
  
  apply_policy "brave_optimizations"
  apply_policy "adblock"
  apply_policy "privacy"
  apply_policy "ui"
  apply_policy "features"
  create_desktop_entry
  
  log_message "Installing recommended extensions..."
  install_extension_from_crx "cjpalhdlnbpafiamejdnhcphjbkeiagm" "uBlock Origin" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.crx"
  install_extension_from_crx "eimadpbcbfnmbkopoojfekhnkhdbieeh" "Dark Reader" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh.crx"
  install_theme "annfbnbieaamhaimclajlajpijgkdblo" "Dark Theme for Google Chrome" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/themes/annfbnbieaamhaimclajlajpijgkdblo.crx"
  
  LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
  if [[ -f "${LOCAL_STATE}" ]]; then
    if jq -e '.browser.enabled_labs_experiments' "${LOCAL_STATE}" >/dev/null 2>&1; then
      jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
    else
      jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
    fi
    mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
    log_message "Enabled advanced ad blocking flag in browser flags"
  fi
  
  # Bundle Option 14
  install_dashboard_customizer
  
  log_message "Default optimizations and dashboard customizer applied successfully"
  log_message "Please restart Brave browser for changes to take effect"
}

update_desktop_with_extensions() {
  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  
  log_message "Updating desktop entry with installed extensions..."
  
  if [[ ! -f "$desktop_file" ]]; then
    create_desktop_entry
  fi
  
  local brave_exec=$(grep "^Exec=" "$desktop_file" | head -1 | sed -E 's/Exec=([^ ]+).*/\1/')
  local extensions_dir="/usr/share/brave/extensions"
  local dashboard_dir="/usr/share/brave/dashboard-extension"
  local extension_paths=""
  
  if [[ -d "$dashboard_dir" ]]; then
    extension_paths="$dashboard_dir"
  fi
  if [[ -d "$extensions_dir" ]]; then
    for ext_dir in "$extensions_dir"/*; do
      if [[ -d "$ext_dir" && "$ext_dir" != "$dashboard_dir" ]]; then
        if [[ -n "$extension_paths" ]]; then
          extension_paths="${extension_paths},${ext_dir}"
        else
          extension_paths="${ext_dir}"
        fi
      fi
    done
  fi
  
  if [[ -n "$extension_paths" ]]; then
    local temp_file=$(mktemp)
    while IFS= read -r line; do
      if [[ "$line" =~ ^Exec= ]]; then
        if [[ "$line" =~ --load-extension= ]]; then
          line=$(echo "$line" | sed -E "s|(--load-extension=)[^ ]*|\1$extension_paths|")
        else
          line="Exec=${brave_exec} --load-extension=${extension_paths} $(echo "$line" | sed -E "s|^Exec=${brave_exec} ?||")"
        fi
        if ! [[ "$line" =~ --homepage= ]]; then
          line="${line} --homepage=chrome://newtab"
        fi
      fi
      echo "$line" >> "$temp_file"
    done < "$desktop_file"
    mv "$temp_file" "$desktop_file"
    chmod 644 "$desktop_file"
    log_message "Desktop entry updated with all installed extensions"
  else
    log_message "No extra extensions to update in desktop entry"
  fi
}

set_brave_dark_mode() {
  local policy_file="${POLICY_DIR}/dark_mode.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Dark mode is already enabled"
  else
    cat > "$policy_file" << EOF
{
  "ForceDarkModeEnabled": true
}
EOF
    chmod 644 "$policy_file"
    touch "/tmp/brave_debloat_dark_mode"
    log_message "Dark mode enabled"
  fi
  
  update_desktop_with_extensions
  pkill -9 -f "brave.*" || true
  log_message "Brave restarted to apply dark mode"
}

toggle_hardware_acceleration() {
  local policy_file="${POLICY_DIR}/hardware.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Hardware acceleration is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      cat > "${policy_file}" << EOF
{
  "HardwareAccelerationModeEnabled": false
}
EOF
      chmod 644 "${policy_file}"
      log_message "Hardware acceleration disabled"
    else
      log_message "Hardware acceleration remains enabled"
    fi
  else
    cat > "${policy_file}" << EOF
{
  "HardwareAccelerationModeEnabled": true
}
EOF
    chmod 644 "${policy_file}"
    log_message "Hardware acceleration enabled"
  fi
}

toggle_analytics() {
  local policy_file="${POLICY_DIR}/privacy.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Analytics and data collection are currently DISABLED"
    read -p "Would you like to enable them? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Analytics and data collection enabled"
    else
      log_message "Analytics and data collection remain disabled"
    fi
  else
    cat > "${policy_file}" << EOF
{
  "MetricsReportingEnabled": false,
  "CloudReportingEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "AutomaticallySendAnalytics": false,
  "DnsOverHttpsMode": "automatic"
}
EOF
    chmod 644 "${policy_file}"
    log_message "Analytics and data collection disabled"
  fi
}

toggle_custom_scriptlets() {
  local policy_file="${POLICY_DIR}/scriptlets.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Custom scriptlets are currently ENABLED"
    read -p "Would you like to disable them? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Custom scriptlets disabled"
    else
      log_message "Custom scriptlets remain enabled"
    fi
  else
    log_message "WARNING: This feature is experimental and for advanced users only."
    read -p "Enable custom scriptlets? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      cat > "${policy_file}" << EOF
{
  "EnableCustomScriptlets": true
}
EOF
      chmod 644 "${policy_file}"
      log_message "Custom scriptlets enabled"
    fi
  fi
}

toggle_background_running() {
  local policy_file="${POLICY_DIR}/background.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Background running is currently DISABLED"
    read -p "Would you like to enable it? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Background running enabled"
    else
      log_message "Background running remains disabled"
    fi
  else
    log_message "WARNING: Disabling background running may cause instability."
    read -p "Disable background running? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      cat > "${policy_file}" << EOF
{
  "BackgroundModeEnabled": false
}
EOF
      chmod 644 "${policy_file}"
      log_message "Background running disabled"
    fi
  fi
}

toggle_memory_saver() {
  local policy_file="${POLICY_DIR}/memory_saver.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Memory saver is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Memory saver disabled"
    else
      log_message "Memory saver remains enabled"
    fi
  else
    cat > "${policy_file}" << EOF
{
  "MemorySaverModeEnabled": true
}
EOF
    chmod 644 "$policy_file"
    log_message "Memory saver enabled"
  fi
}

toggle_ui_improvements() {
  toggle_policy "ui" "UI Improvements"
}

toggle_brave_features() {
  toggle_policy "features" "Brave Rewards/VPN/Wallet"
}

toggle_experimental_adblock() {
  LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
  
  if [[ -f "${LOCAL_STATE}" ]] && jq -e '.browser.enabled_labs_experiments | index("brave-adblock-experimental-list-default@1")' "${LOCAL_STATE}" >/dev/null 2>&1; then
    log_message "Experimental ad blocking is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      local temp_file="${LOCAL_STATE}.tmp"
      jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default@1"))' "${LOCAL_STATE}" > "$temp_file"
      mv "$temp_file" "${LOCAL_STATE}"
      log_message "Experimental ad blocking disabled"
    else
      log_message "Experimental ad blocking remains enabled"
    fi
  else
    log_message "Enabling experimental ad blocking..."
    if [[ -f "${LOCAL_STATE}" ]]; then
      if jq -e '.browser.enabled_labs_experiments' "${LOCAL_STATE}" >/dev/null 2>&1; then
        jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
      else
        jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
      fi
      mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
    else
      echo '{"browser": {"enabled_labs_experiments": ["brave-adblock-experimental-list-default@1"]}}' > "${LOCAL_STATE}"
    fi
    chmod 644 "${LOCAL_STATE}"
    log_message "Experimental ad blocking enabled"
  fi
}

install_recommended_extensions() {
  log_message "Loading recommended extensions..."
  
  local temp_file=$(mktemp)
  if ! download_file "${GITHUB_BASE}/policies/consolidated_extensions.json" "$temp_file"; then
    log_error "Failed to download extension data"
    rm "$temp_file"
    return 1
  fi

  local ext_count=$(jq '[.categories | to_entries[] | select(.key != "themes") | .value[]] | length' "$temp_file")
  if [ "$ext_count" -eq 0 ]; then
    log_error "No extensions found in the extensions data (check consolidated_extensions.json structure)"
    cat "$temp_file"
    rm "$temp_file"
    return 1
  fi

  clear
  echo "=== Recommended Extensions ==="
  local i=1
  declare -A ext_map
  
  local recommended_ids=$(jq -r '.recommended_ids[]' "$temp_file" | tr '\n' ' ')
  
  while read -r id && read -r name && read -r description && read -r crx_url; do
    local mark=""
    if echo "$recommended_ids" | grep -q "$id"; then
      mark="*"
    fi
    printf "%2d. %-35s - %s %s\n" "$i" "$name" "$description" "$mark"
    ext_map["$i"]="$id|$name|$crx_url"
    ((i++))
  done < <(jq -r '.categories | to_entries[] | select(.key != "themes") | .value[] | (.id, .name, .description // "No description", .crx_url)' "$temp_file")
  
  echo -e "\n* = Recommended extension"
  echo -e "Select extensions to install (e.g., '1 3 5' or 'all' for all, '0' to exit): "
  read -p "> " choices
  
  if [[ "$choices" == "0" ]]; then
    log_message "Exiting extension installer"
    rm "$temp_file"
    return 0
  elif [[ "$choices" == "all" ]]; then
    for key in "${!ext_map[@]}"; do
      IFS='|' read -r id name crx_url <<< "${ext_map[$key]}"
      install_extension_from_crx "$id" "$name" "$crx_url"
    done
  else
    IFS=' ' read -ra selected_options <<< "$choices"
    for choice in "${selected_options[@]}"; do
      if [[ -n "${ext_map[$choice]}" ]]; then
        IFS='|' read -r id name crx_url <<< "${ext_map[$choice]}"
        install_extension_from_crx "$id" "$name" "$crx_url"
      else
        log_error "Invalid selection: $choice"
      fi
    done
  fi
  
  update_desktop_with_extensions
  rm "$temp_file"
  log_message "Selected extensions processed"
}

install_dashboard_customizer() {
  local ext_id="dashboard-customizer"
  local ext_name="Dashboard Customizer"
  local crx_url="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/brave-dashboard-customizer/brave-dashboard-customizer.crx"
  local ext_dir="/usr/share/brave/dashboard-extension"
  
  log_message "Installing ${ext_name}..."
  
  local crx_path="/usr/share/brave/${ext_id}.crx"
  if [[ -d "$ext_dir" ]]; then
    log_message "Removing old ${ext_name} install for fresh copy..."
    rm -rf "$ext_dir"
  fi
  if download_file "$crx_url" "$crx_path"; then
    chmod 644 "$crx_path"
    if [[ ! -s "$crx_path" ]]; then
      log_error "Downloaded ${crx_path} is empty or invalid"
      ls -l "$crx_path"
      return 1
    fi
    mkdir -p "$ext_dir"
    log_message "Unzipping ${crx_path} to ${ext_dir}..."
    unzip -o -q "$crx_path" -d "$ext_dir"
    rm -rf "$ext_dir/_metadata"
    if [[ ! -f "$ext_dir/manifest.json" ]]; then
      log_error "Manifest file missing in ${ext_dir}"
      ls -l "$ext_dir"
      unzip -l "$crx_path"
      return 1
    fi
    log_message "${ext_name} installed successfully"
  else
    log_error "Failed to download ${ext_name} from ${crx_url}"
    return 1
  fi
  
  local policy_file="${POLICY_DIR}/extension_settings.json"
  if [[ -f "$policy_file" ]]; then
    jq ".ExtensionSettings[\"${ext_id}\"] = {\"installation_mode\": \"normal_installed\", \"update_url\": \"https://clients2.google.com/service/update2/crx\", \"toolbar_pin\": \"force_pinned\"}" "$policy_file" > "$policy_file.tmp"
    mv "$policy_file.tmp" "$policy_file"
  else
    cat > "$policy_file" << EOF
{
  "ExtensionSettings": {
    "${ext_id}": {
      "installation_mode": "normal_installed",
      "update_url": "https://clients2.google.com/service/update2/crx",
      "toolbar_pin": "force_pinned"
    }
  }
}
EOF
  fi
  chmod 644 "$policy_file"
  
  local prefs_file="${BRAVE_PREFS}"
  mkdir -p "${PREFERENCES_DIR}"
  if [[ ! -f "$prefs_file" ]]; then
    echo "{}" > "$prefs_file"
    chmod 644 "$prefs_file"
  fi
  jq '.brave.new_tab_page = (.brave.new_tab_page // {}) | 
      .brave.new_tab_page.show_background_image = false | 
      .brave.new_tab_page.show_stats = false | 
      .brave.new_tab_page.show_shortcuts = false | 
      .brave.new_tab_page.show_branded_background_image = false | 
      .brave.new_tab_page.show_cards = false | 
      .brave.new_tab_page.show_search_widget = false | 
      .brave.new_tab_page.show_clock = false | 
      .brave.new_tab_page.show_brave_news = false | 
      .brave.new_tab_page.show_together = false' "$prefs_file" > "$prefs_file.tmp" || {
    log_error "Failed to update Preferences"
    cat "$prefs_file.tmp"
    return 1
  }
  mv "$prefs_file.tmp" "$prefs_file"
  chmod 644 "$prefs_file"
  log_message "Stripped Brave dashboard features for ${ext_name}"

  rm -rf "${HOME}/.cache/BraveSoftware/Brave-Browser/*"
  log_message "Cleared Brave cache to enforce ${ext_name}"

  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  if [[ -f "$desktop_file" ]]; then
    local brave_exec=$(grep "^Exec=" "$desktop_file" | head -1 | sed -E 's/Exec=([^ ]+).*/\1/')
    local temp_file=$(mktemp)
    while IFS= read -r line; do
      if [[ "$line" =~ ^Exec= ]]; then
        line="Exec=${brave_exec} --load-extension=${ext_dir} --homepage=chrome://newtab"
      fi
      echo "$line" >> "$temp_file"
    done < "$desktop_file"
    mv "$temp_file" "$desktop_file"
    chmod 644 "$desktop_file"
    log_message "Updated desktop entry to enforce ${ext_name} at startup"
  fi

  pkill -9 -f "brave.*" || true
  log_message "All Brave processes killed to apply ${ext_name}"
}

show_menu() {
  clear
  echo "
██████╗ ██████╗ █████╗ ██╗   ██╗███████╗     ██████╗ ███████╗██████╗ ██╗      ██████╗  █████╗ ████████╗
██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔════╝    ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗██╔══██╗╚══██╔══╝
██████╔╝██████╔╝███████║██║   ██║█████╗      ██║  ██║█████╗  ██████╔╝██║     ██║   ██║███████║   ██║   
██╔══██╗██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝      ██║  ██║██╔══╝  ██╔══██╗██║     ██║   ██║██╔══██║   ██║   
██████╔╝██║  ██║██║  ██║ ╚████╔╝ ███████╗    ██████╔╝███████╗██████╔╝███████╗╚██████╔╝██║  ██║   ██║   
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝    ╚═════╝ ╚══════╝╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
"

  echo "A script to debloat Brave browser and apply optimizations..."
  echo "*Note I am working on a new version of this script to cover smoothbrain Win and Mac users."
  echo
  echo "=== Brave Browser Optimization Menu ==="
  echo "1. Apply Default Optimizations (Recommended)"
  echo "   Enables core performance features, removes bloat, and installs uBlock Origin, Dark Reader, and Dashboard Customizer"
  echo
  echo "2. Install Brave and apply optimizations"
  echo "   Install Brave browser and apply recommended optimizations"
  echo
  echo "3. Change Search Engine"
  echo "   Choose from DuckDuckGo, SearXNG, Whoogle or traditional options"
  echo
  echo "4. Toggle Hardware Acceleration"
  echo "   Improves rendering performance using your GPU"
  echo
  echo "5. Disable Analytics & Data Collection"
  echo "   Stops background analytics and telemetry"
  echo
  echo "6. Enable Custom Scriptlets (Advanced)"
  echo "   WARNING: Only for advanced users. Allows custom JavaScript injection"
  echo
  echo "7. Disable Background Running"
  echo "   WARNING: May cause instability"
  echo
  echo "8. Toggle Memory Saver"
  echo "   Reduces memory usage by suspending inactive tabs"
  echo
  echo "9. UI Improvements"
  echo "   Shows full URLs, enables wide address bar, and bookmarks bar"
  echo
  echo "10. Dashboard Customization"
  echo "    Removes widgets and customizes the new tab page"
  echo
  echo "11. Remove Brave Rewards/VPN/Wallet"
  echo "    Disables cryptocurrency and rewards features"
  echo
  echo "12. Toggle Experimental Ad Blocking (experimental)"
  echo "    Enhanced ad blocking - Will check current status"
  echo
  echo "13. Install Recommended Brave extensions"
  echo "    Installs a curated set of recommended extensions"
  echo
  echo "14. Install Dashboard Customizer Extension"
  echo "    Replaces Brave's dashboard with a clean, black background and clock"
  echo
  echo "15. Enable Dark Mode"
  echo "    Forces Brave to use dark theme regardless of system settings"
  echo
  echo "16. Install Browser Theme"
  echo "    Choose from a selection of browser themes"
  echo
  echo "17. Revert All Changes"
  echo "    Removes all changes made by this script"
  echo
  echo "18. Exit"
  echo
  echo "You can select multiple options by entering numbers separated by spaces (e.g., 4 5 8)"
  echo "Note: Options 1, 2, and 17 cannot be combined with other options"
  echo
}

main() {
  locate_brave_files
  
  while true; do
    show_menu
    
    read -p "Enter your choice(s) [1-18]: " choices
    
    IFS=' ' read -ra selected_options <<< "$choices"
    
    local has_exclusive=0
    for choice in "${selected_options[@]}"; do
      if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "17" ]]; then
        has_exclusive=1
        break
      fi
    done
    
    if [[ $has_exclusive -eq 1 && ${#selected_options[@]} -gt 1 ]]; then
      log_error "Options 1, 2, and 17 cannot be combined with other options"
      sleep 2.5
      continue
    fi
    
    for choice in "${selected_options[@]}"; do
      case ${choice} in
        1)
          apply_default_optimizations
          sleep 2.5
          ;;
        2)
          install_brave_and_optimize
          sleep 2.5
          ;;
        3)
          set_search_engine
          sleep 2.5
          ;;
        4)
          toggle_hardware_acceleration
          sleep 2.5
          ;;
        5)
          toggle_analytics
          sleep 2.5
          ;;
        6)
          toggle_custom_scriptlets
          sleep 2.5
          ;;
        7)
          toggle_background_running
          sleep 2.5
          ;;
        8)
          toggle_memory_saver
          sleep 2.5
          ;;
        9)
          toggle_ui_improvements
          sleep 2.5
          ;;
        10)
          modify_dashboard_preferences
          sleep 2.5
          ;;
        11)
          toggle_brave_features
          sleep 2.5
          ;;
        12)
          toggle_experimental_adblock
          sleep 4
          ;;
        13)
          install_recommended_extensions
          sleep 2.5
          ;;
        14)
          install_dashboard_customizer
          sleep 2.5
          ;;
        15)
          set_brave_dark_mode
          sleep 2.5
          ;;
        16)
          select_theme
          sleep 2.5
          ;;
        17)
          read -p "Are you sure you want to revert all changes? (y/n): " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            revert_all_changes
          fi
          sleep 2.5
          ;;
        18)
          log_message "Exiting...
Thank you for using Brave debloat, lets make Brave great again."
          sleep 2.5
          exit 0
          ;;
        *)
          log_error "Invalid option: $choice"
          sleep 2.5
          ;;
      esac
    done
    
    if [ ${#selected_options[@]} -gt 0 ]; then
      log_message "All selected options have been processed."
      log_message "Please restart Brave browser for all changes to take effect."
      sleep 2.5
    fi
  done
}

revert_all_changes() {
  log_message "Reverting all changes..."
  
  rm -rf "${POLICY_DIR}"/*
  rm -rf "/usr/share/brave/extensions"/*
  rm -rf "/usr/share/brave/themes"/*
  rm -rf "/usr/share/brave/dashboard-extension"/*
  rm -f "/usr/local/bin/brave-debloat-wrapper"
  rm -f "/usr/share/applications/brave-debloat.desktop"
  rm -f "/tmp/brave_debloat_dark_mode"
  
  if [[ -f "${BRAVE_PREFS}" ]]; then
    rm -f "${BRAVE_PREFS}"
  fi
  
  if [[ -f "${PREFERENCES_DIR%/*}/Local State" ]]; then
    rm -f "${PREFERENCES_DIR%/*}/Local State"
  fi
  
  log_message "All changes reverted"
}

# Check for required dependencies
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Please install it first." >&2
  echo "Debian/Ubuntu: sudo apt install jq" >&2
  echo "Fedora:        sudo dnf install jq" >&2
  echo "Arch:          sudo pacman -S jq" >&2
  exit 1
fi

main
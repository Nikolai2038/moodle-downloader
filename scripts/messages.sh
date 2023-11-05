#!/bin/bash

# (REUSE) Special function to get current script file hash
function get_text_hash() {
  echo "${*}" | sha256sum | cut -d ' ' -f 1 || return "$?"
  return 0
}

# (REUSE) Source this file only if wasn't sourced already
{
  current_file_path="$(realpath "${BASH_SOURCE[0]}")" || exit "$?"
  current_file_hash="$(echo "${current_file_path}" | sha256sum | cut -d ' ' -f 1)" || exit "$?"
  current_file_is_sourced_variable_name="FILE_IS_SOURCED_${current_file_hash^^}"
  current_file_is_sourced="$(eval "echo \"\${${current_file_is_sourced_variable_name}}\"")" || exit "$?"
  if [ -n "${current_file_is_sourced}" ]; then
    return
  fi
  eval "export ${current_file_is_sourced_variable_name}=1" || exit "$?"
  if [ "${IS_DEBUG_BASH}" == "1" ]; then
    if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
      echo "Executing \"${current_file_path}\"..." >&2
    else
      echo "Sourcing \"${current_file_path}\"..." >&2
    fi
  fi
}

# (REUSE) Prepare before imports
{
  # Because variables is the same when sourcing, we depend on file hash.
  # Also, we don't use variable for variable name here, because it will fall in the same problem.
  eval "source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")=\"${PWD}\"" || exit "$?"

  # We use "cd" instead of specifying file paths directly in the "source" comment, because these comments do not change when files are renamed or moved.
  # Moreover, we need to specify exact paths in "source" to use links to function and variables between files (language server).
  cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" || exit "$?"
}

# Imports
# ...

# (REUSE) Prepare after imports
{
  eval "cd \"\${source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")}\"" || exit "$?"
}

# ========================================
# Colors for messages
# ========================================
# Color for message
export C_INFO='\e[0;36m'
# Color for successful execution
export C_SUCCESS='\e[0;32m'
# Color for highlighted text
export C_HIGHLIGHT='\e[1;95m'
# Color for error
export C_WARNING='\e[0;33m'
# Color for error
export C_ERROR='\e[0;31m'

# Reset color
export C_RESET='\e[0m'

# Special text that will be replaced with the previous one
export C_RETURN='COLOR_RETURN'
# ========================================

# Prints a message with the specified prefix and text
function print_color_message() {
  local main_color="${1}" && shift
  local text="${1}" && shift

  # Replaces the special string with the text color
  # (don't forget to escape the first color character with an additional backslash)
  if [ -n "${main_color}" ]; then
    text=$(echo -e "${text}" | sed -E "s/${C_RETURN}/\\${main_color}/g") || return "$?"
  else
    text=$(echo -e "${text}" | sed -E "s/${C_RETURN}//g") || return "$?"
  fi

  # shellcheck disable=SC2320
  echo -e "${main_color}${text}${C_RESET}" || return "$?"

  return 0
}

# Prints a message with information
function print_info() {
  local text="${1}" && shift
  print_color_message "${C_INFO}" "${text}" >&2 || return "$?"
  return 0
}

# Prints a message about success
function print_success() {
  local text="${1}" && shift
  print_color_message "${C_SUCCESS}" "${text}" >&2 || return "$?"
  return 0
}

# Prints highlighted message
function print_highlight() {
  local text="${1}" && shift
  print_color_message "${C_HIGHLIGHT}" "${text}" >&2 || return "$?"
  return 0
}

# Prints a warning message
function print_warning() {
  local text="${1}" && shift
  print_color_message "${C_WARNING}" "${text}" >&2 || return "$?"
  return 0
}

# Prints an error message
function print_error() {
  local text="${1}" && shift
  print_color_message "${C_ERROR}" "${text}" >&2 || return "$?"
  return 0
}

# (REUSE) Add ability to execute script by itself (for debugging)
{
  if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    print_color_message "$@" || exit "$?"
  fi
}

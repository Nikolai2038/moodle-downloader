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
source "../messages.sh" || exit "$?"
source "../variable/variables_must_be_specified.sh" || exit "$?"

# (REUSE) Prepare after imports
{
  eval "cd \"\${source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")}\"" || exit "$?"
}

function download_file_or_use_cached() {
  local is_disable_cache="${1}" && shift
  local cache_directory="${1}" && shift
  local link="${1}" && shift
  variables_must_be_specified "is_disable_cache" "cache_directory" "link" || return "$?"

  local file_name
  file_name="$(echo "${link}" | sed -E 's/[^A-Za-z0-9\-_]/_/g')" || return "$?"
  local file_path="${cache_directory}/${file_name}"

  # Download course page if not already downloaded
  if [ ! -f "${file_path}" ] || ((is_disable_cache)); then
    curl "${link}" "${@}" > "${file_path}" || return "$?"
  fi

  local course_page_content
  course_page_content="$(cat "${file_path}")" || return "$?"

  if echo "${course_page_content}" | grep '<title>Перенаправление</title>' > /dev/null; then
    # Clear file
    rm "${file_path}" || return "$?"

    print_error "Page content was not loaded. Update your cookie value!" || return "$?"
    return 1
  fi

  echo "${course_page_content}"

  return 0
}

# (REUSE) Add ability to execute script by itself (for debugging)
{
  if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    download_file_or_use_cached "$@" || exit "$?"
  fi
}

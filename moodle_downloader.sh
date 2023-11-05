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
source "./env.sh" || exit "$?"
source "./scripts/xpath/get_node_with_attribute_value.sh" || exit "$?"

# (REUSE) Prepare after imports
{
  eval "cd \"\${source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")}\"" || exit "$?"
}

DIRECTORY_WITH_THIS_SCRIPT="$(realpath "$(dirname "${BASH_SOURCE[0]}")")" || exit "$?"
DOWNLOADS_DIRECTORY="${DIRECTORY_WITH_THIS_SCRIPT}/downloads"

# Start main script of Automata Parser
function moodle_downloader() {
  if [ ! -d "${DOWNLOADS_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_DIRECTORY}" || return "$?"
  fi

  local course_file_name
  course_file_name="$(echo "${LINK}" | sed -E 's/[^A-Za-z0-9\-_]/_/g')" || return "$?"
  local course_file_path="${DOWNLOADS_DIRECTORY}/${course_file_name}"

  # Download course page if not already downloaded
  if [ ! -f "${course_file_path}" ]; then
    curl "${LINK}" \
      --compressed \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:119.0) Gecko/20100101 Firefox/119.0' \
      -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br' \
      -H 'DNT: 1' \
      -H 'Connection: keep-alive' \
      -H "Cookie: ${COOKIE}" \
      -H 'Upgrade-Insecure-Requests: 1' \
      -H 'Sec-Fetch-Dest: document' \
      -H 'Sec-Fetch-Mode: navigate' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'Sec-Fetch-User: ?1' \
      -H 'Sec-GPC: 1' > "${course_file_path}" || return "$?"
  fi

  local course_page_content
  course_page_content="$(cat "${course_file_path}")" || return "$?"

  local course_page_content_body
  course_page_content_body="<body${course_page_content#*"<body"}" || return "$?"
  course_page_content_body="${course_page_content_body%"</body>"*}</body>" || return "$?"

  # Fix "undefined entity" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/&[a-z]+;//g')" || return "$?"
  # Fix "mismatched tag" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(<(img|input)[^>]+[^\/]\s*)>/\1\/>/g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/<br\s*>/<br\/>/g')" || return "$?"

  # TODO: Find a way to remove multiline "<input>" tags
  course_page_content_body="$(echo "${course_page_content_body//'data-region="view-overview-search-input"
'/'data-region="view-overview-search-input"'}" | sed -E 's/(data-region="view-overview-search-input")\s*/\1\//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body//'data-region="search-input"
'/'data-region="search-input"'}" | sed -E 's/(data-region="search-input")\s*/\1\//g')" || return "$?"
  course_page_content_body="${course_page_content_body//'
                                            <input
                                                type="radio"
                                                name="message_blocknoncontacts"
                                                class="custom-control-input"
                                                id="block-noncontacts-6547ed21197396547ed21188162-1"
                                                value="1"
                                            >'/''}" || return "$?"
  course_page_content_body="${course_page_content_body//'
                                            <input
                                                type="radio"
                                                name="message_blocknoncontacts"
                                                class="custom-control-input"
                                                id="block-noncontacts-6547ed21197396547ed21188162-0"
                                                value="0"
                                            >'/''}" || return "$?"

  # Fix "not well-formed (invalid token)" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(data-route-back|data-auto-rows)//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/data-category="[^"]+"//g')" || return "$?"

  get_node_with_attribute_value "${course_page_content_body}" "a" "class" "aalink" || return "$?"

  return 0
}

# (REUSE) Add ability to execute script by itself (for debugging)
{
  if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    moodle_downloader "$@" || exit "$?"
  fi
}

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
source "./scripts/xpath/get_node_attribute_value.sh" || exit "$?"
source "./scripts/xpath/get_nodes_count.sh" || exit "$?"
source "./scripts/xpath/get_xml_content.sh" || exit "$?"
source "./scripts/curl/download_file_or_use_cached.sh" || exit "$?"

# (REUSE) Prepare after imports
{
  eval "cd \"\${source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")}\"" || exit "$?"
}

DIRECTORY_WITH_THIS_SCRIPT="$(realpath "$(dirname "${BASH_SOURCE[0]}")")" || exit "$?"
DOWNLOADS_DIRECTORY="${DIRECTORY_WITH_THIS_SCRIPT}/downloads"
DOWNLOADS_HTML_DIRECTORY="${DOWNLOADS_DIRECTORY}/cache"
DOWNLOADS_COURSES_DIRECTORY="${DOWNLOADS_DIRECTORY}/courses"
PREFIX_TAB="  "
CURL_EXTRA_ARGS=(
  --compressed
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:119.0) Gecko/20100101 Firefox/119.0'
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
  -H 'Accept-Language: en-US,en;q=0.5'
  -H 'Accept-Encoding: gzip, deflate, br'
  -H 'DNT: 1'
  -H 'Connection: keep-alive'
  -H "Cookie: ${COOKIE}"
  -H 'Upgrade-Insecure-Requests: 1'
  -H 'Sec-Fetch-Dest: document'
  -H 'Sec-Fetch-Mode: navigate'
  -H 'Sec-Fetch-Site: same-origin'
  -H 'Sec-Fetch-User: ?1'
  -H 'Sec-GPC: 1'
)
IS_DISABLE_CACHE=0

# Start main script of Automata Parser
function moodle_downloader() {
  if [ ! -d "${DOWNLOADS_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_DIRECTORY}" || return "$?"
  fi
  if [ ! -d "${DOWNLOADS_HTML_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_HTML_DIRECTORY}" || return "$?"
  fi
  if [ ! -d "${DOWNLOADS_COURSES_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_COURSES_DIRECTORY}" || return "$?"
  fi

  local course_page_content
  course_page_content="$(download_file_or_use_cached "${IS_DISABLE_CACHE}" "${DOWNLOADS_HTML_DIRECTORY}" "${LINK}" "${CURL_EXTRA_ARGS[@]}")" || return "$?"

  local course_page_content_body
  course_page_content_body="<body${course_page_content#*"<body"}" || return "$?"
  course_page_content_body="${course_page_content_body%"</body>"*}</body>" || return "$?"

  # Fix "undefined entity" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/&[a-z]+;//g')" || return "$?"
  # Fix "mismatched tag" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(<(img)[^>]+[^\/]\s*)>/\1\/>/g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/<br\s*>/<br\/>/g')" || return "$?"

  # "<input>" tag is not closed in the recieved HTML, so Xpath return error with it.
  # So we need to remove it.
  # We use replace "\n" to "\r" to replace multiline "<input>".
  course_page_content_body="$(echo "${course_page_content_body}" | tr '\n' '\r' | sed -E 's/<input([^>]*[\r]*)*>//g' | tr '\r' '\n')" || return "$?"

  # Fix "not well-formed (invalid token)" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(data-route-back|data-auto-rows)//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/data-category="[^"]+"//g')" || return "$?"

  # Get course title
  local page_title_header_xml
  page_title_header_xml="$(get_node_with_attribute_value "${course_page_content_body}" "h3" "class" "page-title mb-0")" || return "$?"
  local page_title
  page_title="$(get_xml_content "${page_title_header_xml}")" || return "$?"
  print_success "Course title derived successfully: ${C_HIGHLIGHT}${page_title}${C_RETURN}" || return "$?"

  local course_result_directory_path
  course_result_directory_path="${DOWNLOADS_COURSES_DIRECTORY}/$(echo "${page_title}" | sed -E 's/[^a-zA-Zа-яА-Я0-9_. ]/_/g')" || return "$?"
  if [ ! -d "${course_result_directory_path}" ]; then
    mkdir "${course_result_directory_path}" || return "$?"
  fi

  local sections_xml
  # We remove new lines because we need to create array from lines after we got sections
  sections_xml="$(get_node_with_attribute_value "${course_page_content_body//'
'/}" "li" "class" "section main p-3 rounded clearfix")" || return "$?"
  local sections_count
  sections_count="$(get_nodes_count "${sections_xml}" "li")" || return "$?"
  if ((sections_count == 0)); then
    print_error "Sections HTML is empty!"
    return 1
  fi

  declare -a sections
  mapfile -t sections <<< "${sections_xml}" || return "$?"

  local section_xml
  for section_xml in "${sections[@]}"; do
    local section_header_xml
    section_header_xml="$(get_node_with_attribute_value "${section_xml}" "span" "class" "hidden sectionname")" || return "$?"

    # Name of the section
    local section_name
    section_name="$(get_xml_content "${section_header_xml}")" || return "$?"

    print_success "Section derived successfully: ${C_HIGHLIGHT}${section_name}${C_RETURN}" || return "$?"

    local section_links_xml
    section_links_xml="$(get_node_with_attribute_value "${section_xml}" "a" "class" "aalink")" || return "$?"
    local section_links_count
    section_links_count="$(get_nodes_count "${section_links_xml}" "a")" || return "$?"
    print_info "${PREFIX_TAB}Section contains ${C_HIGHLIGHT}${section_links_count}${C_RETURN} links." || return "$?"
    if ((section_links_count == 0)); then
      continue
    fi

    local links_as_string
    links_as_string="$(get_node_attribute_value "${section_links_xml}" "a" "href")" || return "$?"

    declare -a links
    mapfile -t links <<< "${links_as_string}" || return "$?"

    local link
    for link in "${links[@]}"; do
      print_info "${PREFIX_TAB}Link: ${C_HIGHLIGHT}${link}${C_RETURN}" || return "$?"
    done
  done

  return 0
}

# (REUSE) Add ability to execute script by itself (for debugging)
{
  if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    moodle_downloader "$@" || exit "$?"
  fi
}

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
source "./scripts/package/install_command.sh" || exit "$?"

# (REUSE) Prepare after imports
{
  eval "cd \"\${source_previous_directory_$(get_text_hash "${BASH_SOURCE[*]}")}\"" || exit "$?"
}

DIRECTORY_WITH_THIS_SCRIPT="$(realpath "$(dirname "${BASH_SOURCE[0]}")")" || exit "$?"
DOWNLOADS_DIRECTORY="${DIRECTORY_WITH_THIS_SCRIPT}/downloads"
DOWNLOADS_CACHE_DIRECTORY="${DOWNLOADS_DIRECTORY}/cache"
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

function get_body() {
  local html="${1}" && shift

  local course_page_content_body
  course_page_content_body="<body${html#*"<body"}" || return "$?"
  course_page_content_body="${course_page_content_body%"</body>"*}</body>" || return "$?"

  # Fix "undefined entity" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/&[a-z]+;//g')" || return "$?"
  # Fix "mismatched tag" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(<(img|source)[^>]+[^\/]\s*)>/\1\/>/g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/<br\s*>/<br\/>/g')" || return "$?"

  # "<input>" tag is not closed in the recieved HTML, so Xpath return error with it.
  # So we need to remove it.
  # We use replace "\n" to "\r" to replace multiline "<input>".
  course_page_content_body="$(echo "${course_page_content_body}" | tr '\n' '\r' | sed -E 's/<input([^>]*[\r]*)*>//g' | tr '\r' '\n')" || return "$?"

  # Fix "not well-formed (invalid token)" errors
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/ (data-route-back|data-auto-rows|playsinline|controls|selected)//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/data-category="[^"]+"//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/(")(type="video)/\1 \2/g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's/&forceview=1//g')" || return "$?"
  course_page_content_body="$(echo "${course_page_content_body}" | sed -E 's#<script>.*?</script>##g')" || return "$?"

  echo "${course_page_content_body}"

  return 0
}

function get_text_for_filename() {
  echo "${@}" | sed -E 's/[^a-zA-Zа-яА-Я0-9_. ]/_/g' || return "$?"
  return 0
}

# Start main script of Automata Parser
function moodle_downloader() {
  install_command "xpath" "libxml-xpath-perl" || return "$?"

  if [ ! -d "${DOWNLOADS_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_DIRECTORY}" || return "$?"
  fi
  if [ ! -d "${DOWNLOADS_CACHE_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_CACHE_DIRECTORY}" || return "$?"
  fi
  if [ ! -d "${DOWNLOADS_COURSES_DIRECTORY}" ]; then
    mkdir "${DOWNLOADS_COURSES_DIRECTORY}" || return "$?"
  fi

  local course_page_content
  course_page_content="$(download_file_or_use_cached "${IS_DISABLE_CACHE}" "${DOWNLOADS_CACHE_DIRECTORY}" "${LINK}" "${CURL_EXTRA_ARGS[@]}")" || return "$?"

  local course_page_content_body
  course_page_content_body="$(get_body "${course_page_content}")" || return "$?"

  # Get course title
  local page_title_header_xml
  page_title_header_xml="$(get_node_with_attribute_value "${course_page_content_body}" "h3" "class" "page-title mb-0")" || return "$?"
  local page_title
  page_title="$(get_xml_content "${page_title_header_xml}")" || return "$?"
  print_success "Course title derived successfully: ${C_HIGHLIGHT}${page_title}${C_RETURN}" || return "$?"

  local page_title_for_filename
  page_title_for_filename="$(get_text_for_filename "${page_title}")" || return "$?"

  local course_result_directory_path
  course_result_directory_path="${DOWNLOADS_COURSES_DIRECTORY}/${page_title_for_filename}" || return "$?"
  if [ ! -d "${course_result_directory_path}" ]; then
    mkdir "${course_result_directory_path}" || return "$?"
  fi

  local course_cache_directory_path
  course_cache_directory_path="${DOWNLOADS_CACHE_DIRECTORY}/${page_title_for_filename}"
  if [ ! -d "${course_cache_directory_path}" ]; then
    mkdir "${course_cache_directory_path}" || return "$?"
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

  local section_number_in_list=0

  local section_xml
  for section_xml in "${sections[@]}"; do
    ((section_number_in_list++))
    local section_header_xml
    section_header_xml="$(get_node_with_attribute_value "${section_xml}" "span" "class" "hidden sectionname")" || return "$?"

    # Name of the section
    local section_name
    section_name="$(get_xml_content "${section_header_xml}")" || return "$?"

    local section_name_for_filename
    section_name_for_filename="$(get_text_for_filename "${section_name}")" || return "$?"
    local section_directory_path="${course_result_directory_path}/${section_number_in_list} - ${section_name_for_filename}"
    if [ ! -d "${section_directory_path}" ]; then
      mkdir "${section_directory_path}" || return "$?"
    fi

    print_success "Section derived successfully: ${C_HIGHLIGHT}${section_name}${C_RETURN}" || return "$?"

    local section_links_xml
    section_links_xml="$(get_node_with_attribute_value "${section_xml//'
'/}" "a" "class" "aalink")" || return "$?"
    local section_links_count
    section_links_count="$(get_nodes_count "${section_links_xml}" "a")" || return "$?"
    print_info "${PREFIX_TAB}Section contains ${C_HIGHLIGHT}${section_links_count}${C_RETURN} links." || return "$?"
    if ((section_links_count == 0)); then
      continue
    fi

    declare -a links_xml_array
    mapfile -t links_xml_array <<< "${section_links_xml}" || return "$?"

    local link_number_in_list=0

    local link_xml
    for link_xml in "${links_xml_array[@]}"; do
      ((link_number_in_list++))
      # Skip links which are not videolectures
      if echo "${link_xml}" | grep -v "videolecture" > /dev/null; then
        continue
      fi

      local link
      link="$(get_node_attribute_value "${link_xml}" "a" "href")" || return "$?"

      local link_page_content
      link_page_content="$(download_file_or_use_cached "${IS_DISABLE_CACHE}" "${course_cache_directory_path}" "${link}" "${CURL_EXTRA_ARGS[@]}")" || return "$?"

      local link_page_content_body
      link_page_content_body="$(get_body "${link_page_content}")" || return "$?"

      local source_tag
      source_tag="$(get_node_with_attribute_value "${link_page_content_body}" "source" "type" "video/mp4")" || return "$?"

      local video_link
      video_link="$(get_node_attribute_value "${source_tag}" "source" "src")" || return "$?"

      local link_text
      link_text="$(echo "${link_xml}" | sed -En 's/^.*<span class="instancename">\s*([^<]+)\s*<span.*$/\1/p')" || return "$?"

      print_info "${PREFIX_TAB}- ${link_text}: ${video_link}" || return "$?"

      # ========================================
      # Download video
      # ========================================
      local link_text_for_filename
      link_text_for_filename="$(get_text_for_filename "${link_text}")" || return "$?"

      local video_file_path="${section_directory_path}/${link_number_in_list} - ${link_text_for_filename}.mp4"

      # Download course page if not already downloaded
      if [ ! -f "${video_file_path}" ] || ((IS_DISABLE_CACHE)); then
        curl -L -o "${video_file_path}" "${video_link}" || return "$?"
      fi
      # ========================================
    done
  done

  print_success "Parsing complete! Your files are in ${C_HIGHLIGHT}${course_result_directory_path}${C_RETURN}." || return "$?"

  return 0
}

# (REUSE) Add ability to execute script by itself (for debugging)
{
  if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    moodle_downloader "$@" || exit "$?"
  fi
}

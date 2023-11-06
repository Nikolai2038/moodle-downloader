# Moodle Downloader

**EN** | [RU](README_RU.md)

## Description

This Bash-script allows you to download videos from Moodle page.

## Requirements

- Linux or WSL;
- Bash;
- `libxml-xpath-perl` apt-package installed (it will be installed automatically, if not already installed).

Script was tested in WSL Debian on Windows 10.

## Usage

1. Clone the repository:

    ```bash
    git pull https://github.com/Nikolai2038/moodle-downloader.git
    cd moodle-downloader
    ```

2. Copy file `env.sh.example` to `env.sh`;
3. Open browser. Authorize in moodle service and open course you want to download videos from;
4. Copy link to the course and insert it in `env.sh` file - change the `LINK` variable value;
5. In the browser open DevTools via `F12` key;
6. Reload page;
7. On the `Network` tab filter the requests by response type - set `HTML`. There should be one request left;
8. Right click the request and select `Headers` tab for it;
9. Copy `Cookie` header value and insert it in `env.sh` file - change the `COOKIE` variable value;
10. Run script:

    ```bash
    ./moodle_downloader.sh
    ```
    
    After executing command, script will start to download all videos into `./downloads/courses/<course name>/<section number> - <section name>` directory (this directories will be created automatically).
    Videos will be named `<video number> - <video name>.mp4`.

Additionally, script cache all html pages inside `./downloads/cache` directory to reduce the number of requests for repeated script calls.

Script also does not download video, if it's filename exists.
So if you want to redownload videos - just delete them.
Same for html files.

## Contribution

Feel free to contribute via [pull requests](https://github.com/Nikolai2038/moodle-downloader/pulls) or [issues](https://github.com/Nikolai2038/moodle-downloader/issues)!

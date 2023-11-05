# Moodle Downloader

## Usage

1. Clone the repository in Linux or WSL;
2. Copy file `env.sh.example` to `env.sh`;
3. Open browser. Authorize in moodle service and open course you want to download;
4. Copy link to the course and insert it in `cookie.sh` file - change the `LINK` variable value;
5. Open DevTools via `F12` key;
6. Reload page;
7. On the `Network` tab filter the requests by response type - set `HTML`. There should be one request left;
8. Right click the request and select `Headers` tab for it;
9. Copy `Cookie` header value and insert it in `cookie.sh` file - change the `COOKIE` variable value;
10. Run:

    ```bash
    ./moodle_downloader.sh
    ```

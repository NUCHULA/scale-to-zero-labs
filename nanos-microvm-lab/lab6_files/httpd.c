/* httpd.c — guest HTTP server สำหรับ Lab 6 (Nanos unikernel บน Firecracker)
 * ----------------------------------------------------------------------------
 * เล็กที่สุดเท่าที่จะรันได้จริงบน Nanos: ใช้ syscall ตรง ๆ (socket/bind/listen/accept)
 * ไม่มี DNS, ไม่มี thread, ไม่มี fork → static-link แล้วบูตใน unikernel ได้ชัวร์.
 *   GET /healthz        -> 200 "ok"      (ใช้เป็นสัญญาณ service-ready ของ lab)
 *   GET / (หรืออื่น ๆ)  -> 200 + หน้า HTML จาก index.html ถ้ามี / ไม่มีก็หน้า default
 * ฟัง 0.0.0.0:8080 (ตรงกับ DNAT/route ของ host tap ใน fc_driver.py)
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define PORT 8080
#define BUFSZ 8192

static char page[65536];
static int page_len = 0;

static void load_page(void) {
    int fd = open("/index.html", O_RDONLY);
    if (fd < 0) fd = open("index.html", O_RDONLY);
    if (fd >= 0) {
        page_len = (int)read(fd, page, sizeof(page) - 1);
        if (page_len < 0) page_len = 0;
        close(fd);
    }
    if (page_len == 0) {
        const char *def =
            "<!doctype html><meta charset=utf-8>"
            "<title>Nanos on Firecracker</title>"
            "<h1>Hello from a Nanos unikernel</h1>"
            "<p>served live from a Firecracker microVM.</p>";
        page_len = (int)strlen(def);
        memcpy(page, def, page_len);
    }
}

static void send_all(int c, const char *p, int n) {
    int off = 0;
    while (off < n) {
        int w = write(c, p + off, n - off);
        if (w <= 0) break;
        off += w;
    }
}

int main(void) {
    char buf[BUFSZ], hdr[256];
    load_page();

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 1;
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(PORT);
    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) return 2;
    if (listen(s, 64) < 0) return 3;

    for (;;) {
        int c = accept(s, 0, 0);
        if (c < 0) continue;
        int n = read(c, buf, sizeof(buf) - 1);
        if (n <= 0) {
            close(c);
            continue;
        }
        buf[n] = 0;

        if (strncmp(buf, "GET /healthz", 12) == 0) {
            const char *ok =
                "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                "Content-Length: 2\r\nConnection: close\r\n\r\nok";
            send_all(c, ok, (int)strlen(ok));
        } else {
            int hn = snprintf(hdr, sizeof(hdr),
                              "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                              "Content-Length: %d\r\nConnection: close\r\n\r\n",
                              page_len);
            send_all(c, hdr, hn);
            send_all(c, page, page_len);
        }
        close(c);
    }
    return 0;
}

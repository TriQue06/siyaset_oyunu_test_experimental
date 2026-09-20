"""HARİTA EDİTÖRÜ SUNUCUSU.

Tarayıcıdan açılan editörün (tools/map_editor.html) proje dosyalarını doğrudan
OKUYUP YAZABİLMESİ için minik bir yerel sunucu. Dosya seçme/indirme derdi yok:
editör açılır açılmaz haritayı ve verileri yükler, "KAYDET" tuşu da data/
altındaki json'ları yerinde günceller.

    python tools/map_editor.py

Sonra tarayıcıda: http://127.0.0.1:8765/tools/map_editor.html
(Komut çalıştığında tarayıcı kendiliğinden açılır.)

Güvenlik: sadece 127.0.0.1 dinlenir ve YALNIZCA data/ altındaki şu dosyalara
yazılır — başka bir yola yazma isteği reddedilir.
"""

import http.server
import json
import socketserver
import threading
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PORT = 8765

## Editörün yazmasına izin verilen dosyalar (proje köküne göre).
WRITABLE = {
    "data/province_seats.json",
    "data/province_seat_centers.json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self) -> None:  # noqa: N802 (http.server arayüzü)
        if self.path != "/save":
            self.send_error(404, "bilinmeyen adres")
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            target = str(payload["path"])
            data = payload["data"]
        except Exception as error:  # bozuk istek
            self.send_error(400, f"istek okunamadi: {error}")
            return

        if target not in WRITABLE:
            self.send_error(403, f"bu dosyaya yazilamaz: {target}")
            return

        path = ROOT / target
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        body = json.dumps({"ok": True, "path": target, "bytes": path.stat().st_size}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print(f"kaydedildi: {target}")

    def end_headers(self) -> None:
        # Editörü her açışta taze veri gelsin (tarayıcı önbelleğe almasın).
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format: str, *args) -> None:  # sessiz log
        return


def main() -> None:
    url = f"http://127.0.0.1:{PORT}/tools/map_editor.html"
    print("Harita editörü çalışıyor:")
    print("   ", url)
    print("Kapatmak için: Ctrl+C")
    threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nkapatıldı")


if __name__ == "__main__":
    main()

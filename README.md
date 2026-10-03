# Web Image Resizer

Eine leistungsstarke, rein clientseitige Web-App zur Bildbearbeitung, entwickelt mit Flutter.
Da alle Bildverarbeitungen lokal in deinem Browser stattfinden, werden keine Bilder auf externe Server hochgeladen – das garantiert maximale Privatsphäre und schnelle Verarbeitungszeiten.

## ✨ Features (Funktionen der App)

* **Bildgröße ändern:** Skaliere Bilder mit oder ohne Beibehaltung des Seitenverhältnisses. Verschiedene Skalierungs-Algorithmen (Bilinear, Bikubisch, etc.) stehen zur Verfügung.
* **Zuschneiden & Ausrichten:** Bilder flexibel zuschneiden (Frei, 1:1, 16:9, 4:3), rotieren (90°) und spiegeln.
* **Formate & Kompression:** Exportiere als JPG oder PNG. Lege die JPG-Qualität prozentual fest oder gib eine maximale Ziel-Dateigröße (in KB) vor.
* **Erweiterte Bildbearbeitung:**
  * Wasserzeichen-Text hinzufügen
  * Schwarz-Weiß-Filter (Grayscale)
  * Kontrastanpassung (+20%)
* **Datenschutz:** Option zum restlosen Entfernen von EXIF-Metadaten (GPS-Daten, Kamerainfos).
* **Produktivität:** 
  * Drag & Drop Unterstützung
  * Galerie-Funktion zum Halten mehrerer Bilder im Speicher
  * Anpassbare Dateinamen-Muster (z.B. `[original]_[width]x[height]`) beim Speichern
  * Dark Mode / Light Mode Unterstützung

## 🚀 Installation & Deployment (Laragon / Webserver)

Die Flutter Web-App besteht nach dem Kompilieren nur aus statischen Dateien (HTML, CSS, JavaScript). Sie benötigt kein Backend wie PHP oder Node.js und kann auf jedem handelsüblichen Webserver gehostet werden.

### Schritt 1: Kompilieren der App (falls du den Code selbst baust)
Stelle sicher, dass [Flutter](https://flutter.dev/docs/get-started/install) installiert ist, und öffne ein Terminal im Hauptverzeichnis des Projekts. Führe folgenden Befehl aus:
```bash
flutter build web --release
```
Dieser Befehl erstellt den Ordner `build/web/` in deinem Projekt, der alle fertigen Dateien für den Webserver enthält.

*Wichtiger Hinweis zu Unterverzeichnissen:* 
Wenn die App auf deinem Server in einem Unterordner laufen soll (z. B. `http://deinedomain.de/resizer/`), musst du die App mit einem passenden Base-HREF kompilieren:
```bash
flutter build web --release --base-href "/resizer/"
```

### Schritt 2: Bereitstellung auf Laragon (oder XAMPP / Apache / Nginx)
1. Öffne das Dokumentenstammverzeichnis deines Webservers (bei Laragon standardmäßig `C:\laragon\www\`).
2. Erstelle dort einen neuen Ordner für das Projekt, z. B. `C:\laragon\www\resizer\`.
3. Kopiere den **gesamten Inhalt** aus dem zuvor erstellten Ordner `build/web/` in deinen neuen Webserver-Ordner.
4. Starte Apache oder Nginx über die Laragon-Oberfläche.
5. Rufe die App im Browser auf. Bei Laragon z. B. über `http://resizer.test` (falls Auto-Virtual-Hosts aktiv sind und der Ordner `resizer` heißt).

## 🛠️ Technologie
* Framework: [Flutter](https://flutter.dev/) (Web)
* Pakete: `image`, `crop_image`, `desktop_drop`, `file_picker`

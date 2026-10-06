# Privater KI-Server auf dem Raspberry Pi

**Deutsch** | [English](README.en.md)

`setup-ai-phone.sh` verwandelt einen Raspberry Pi in einen privaten KI-Chat-Server, den du von deinem Handy oder Laptop aus erreichen kannst.

```
Android / Laptop
      │  Tailscale HTTPS
      ▼
Open WebUI   127.0.0.1:8080
      │
      ▼
Ollama       127.0.0.1:11434
      │
      ▼
Lokale LLMs (z. B. gemma3:4b)
```

Ollama und Open WebUI lauschen nur auf localhost. Der Fernzugriff läuft ausschließlich über Tailscale Serve, es ist also keine Portweiterleitung im Router nötig.

## Voraussetzungen

- Ein Raspberry Pi mit Raspberry Pi OS / Debian (64-Bit empfohlen) und Internetzugang
- Ein normaler Benutzer mit `sudo`-Rechten
- Mindestens 4 GB freier Speicherplatz (das Skript prüft das)
- [Ollama](https://ollama.com) bereits installiert, am besten mit einem geladenen Modell
- Ein kostenloses [Tailscale](https://tailscale.com)-Konto, Tailscale ist außerdem auf Handy/Laptop installiert

## Erstes Einrichten des Pi (Imager, SSH, Raspberry Pi Connect)

1. **SD-Karte flashen** mit dem [Raspberry Pi Imager](https://www.raspberrypi.com/software/): Gerät und Raspberry Pi OS (64-Bit) wählen. Bei „OS-Anpassung" / „OS customisation" setzen:
   - Hostname (z. B. `raspberrypi`), Benutzername und Passwort
   - WLAN-Zugangsdaten und Land (falls kein LAN-Kabel)
   - **SSH aktivieren** (Passwort oder öffentlicher Schlüssel)
   - **Raspberry Pi Connect** aktivieren, falls deine Imager-Version die Option anbietet (sonst siehe Schritt 4)
2. SD-Karte in den Pi stecken, Strom anschließen und 1–2 Minuten warten.
3. **Erste SSH-Verbindung** vom Laptop im selben Netzwerk:

   ```bash
   ssh <benutzer>@<hostname>.local
   ```

   Falls `.local` nicht aufgelöst wird, nimm die IP-Adresse aus der Geräteliste deines Routers: `ssh <benutzer>@<ip-adresse>`. Die Frage nach dem Fingerabdruck mit `yes` bestätigen, danach das Passwort eingeben.
4. **Raspberry Pi Connect** (falls nicht schon im Imager aktiviert) auf dem Pi einschalten und mit deinem Raspberry-Pi-Konto verbinden:

   ```bash
   sudo apt install -y rpi-connect-lite   # auf Raspberry Pi OS Lite; mit Desktop: rpi-connect
   rpi-connect on
   rpi-connect signin
   ```

   `rpi-connect signin` zeigt eine URL an. Öffne sie am Laptop/Handy, melde dich bei [connect.raspberrypi.com](https://connect.raspberrypi.com) an und bestätige das Gerät. Danach erscheint der Pi dort und lässt sich im Browser per Remote-Shell öffnen (Bildschirmfreigabe nur mit Desktop-Variante).
5. **Zuerst nach dem Login** (siehe unten, „So wird es ausgeführt"): System aktualisieren, `curl`/`git` installieren, Ollama installieren, Repo klonen, Skript starten.

## So wird es ausgeführt

1. Auf einem frischen Raspberry Pi OS zuerst das System aktualisieren und die Grundlagen installieren:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo apt install -y curl git ca-certificates zstd
   ```

2. Ollama installieren und ein Modell laden (überspringen, falls schon erledigt):

   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull gemma3:4b
   ```

3. Das Skript auf den Pi holen:

   ```bash
   git clone https://github.com/johannstrama-YT/raspberry-video-gemma3-4b.git
   cd raspberry-video-gemma3-4b
   ```

4. Als **normaler Benutzer** ausführen (nicht mit `sudo`; das Skript ruft `sudo` selbst auf, wo nötig):

   ```bash
   ./setup-ai-phone.sh
   ```

5. Den Anweisungen folgen:
   - Ist Tailscale noch nicht angemeldet, öffne die angezeigte URL auf Handy/Laptop und bestätige den Pi.
   - Beim ersten Mal musst du eventuell eine zweite URL öffnen, um Tailscale Serve/HTTPS freizugeben. Das Skript wartet bis zu fünf Minuten.

6. Am Ende zeigt das Skript deine private HTTPS-Adresse (`https://<pi-name>.<tailnet>.ts.net`) und einen QR-Code an.

## Nutzung vom Handy

1. Tailscale auf Android installieren und im selben Tailnet anmelden.
2. Den QR-Code scannen (oder die URL im Browser öffnen).
3. Beim ersten Besuch das Open-WebUI-Administratorkonto anlegen, dein Ollama-Modell auswählen und chatten.

## Was das Skript macht

1. Installiert `curl`, `ca-certificates`, `openssl`, `qrencode`
2. Prüft den freien Speicherplatz
3. Prüft, ob Ollama installiert ist
4. Zwingt Ollama, nur auf `127.0.0.1` zu lauschen (systemd-Drop-in)
5. Installiert Tailscale und verbindet es
6. Installiert `uv`
7. Erstellt eine Python-3.11-virtualenv für Open WebUI
8. Installiert Open WebUI (mit Wiederholungsversuchen bei instabilen Downloads)
9. Erstellt und startet einen systemd-Dienst `open-webui`
10. Veröffentlicht Open WebUI in deinem Tailnet mit `tailscale serve`

Das Skript kann gefahrlos erneut ausgeführt werden; es behält den vorhandenen Open-WebUI-Schlüssel und die Daten und aktualisiert Open WebUI.

## Nützliche Befehle

```bash
sudo systemctl status open-webui      # Dienststatus
sudo journalctl -u open-webui -f      # Open-WebUI-Logs
sudo journalctl -u ollama -f          # Ollama-Logs
ollama list                           # installierte Modelle
ollama ps                             # geladene Modelle
sudo tailscale serve status           # private URL anzeigen
watch -n 1 'free -h; echo; ollama ps' # Live-Überwachung von Speicher/Modell
```

## Sicherheit

Aktiviere **kein** Tailscale Funnel, es sei denn, du willst Open WebUI bewusst im öffentlichen Internet freigeben.

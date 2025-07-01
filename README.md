
# Convey: Configuration File Converter

Convey is a shell script tool that centralizes conversions between common configuration file formats (JSON, YAML, XML, .ENV) for DevOps developers. It eliminates manual conversion hassles using `yq` and `jq` under the hood.

## Features
- Cross-format conversions between JSON/YAML/XML/.ENV
- Automatic OS detection (Linux/macOS)
- Self-installing dependencies
- Simple command-line interface

## Installation
```bash
git clone https://github.com/pauloVato-sketch/Convey.git
cd Convey
chmod +x convey.sh
sudo ln -s $(pwd)/convey.sh /usr/local/bin/convey
```
## Examples
```bash
# JSON to YAML
convey config.json yaml
# YAML to .ENV
convey docker-compose.yml env
# XML to JSON
convey data.xml json
```
## Testing

Validated on:

-   MacOS Sequoia
-   AlmaLinux 9
-   Debian (via Docker)
-   Alpine Linux (via Docker)
## Supported Conversions
| Input Format | **JSON** | **YAML** | **XML** | **.ENV** |
|--------------|:--------:|:--------:|:-------:|:--------:|
|   **JSON**   |   **-**  |   **✓**  |  **✓**  |   **✓**  |
|   **YAML**   |   **✓**  |   **-**  |   **✓** |   **✓**  |
|    **XML**   |   **✓**  |   **✓**  |  **-**  |   **✓**  |
|   **.ENV**   |   **✓**  |   **✓**  |  **✓**  |   **-**  |



*Originally developed for the Shell Scripting subject of the Computer Engineer bachelor course at CEFET-MG/UTF-MG.

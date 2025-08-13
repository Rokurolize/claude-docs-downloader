# Claude Code Documentation Downloader

Downloads all Claude Code documentation from Anthropic's official website and saves it locally.

## Quick Start

```bash
# Clone or download this repository
git clone https://github.com/Rokurolize/claude-docs-downloader.git
cd claude-docs-downloader

# Run the downloader
./claude_docs_downloader.sh

# Documentation will be saved to ./claude-code-docs/
```

## Features

- **Auto-discovery**: Finds all documentation pages automatically
- **Differential updates**: Only downloads changed files
- **Change tracking**: Timestamped reports in `reports/` directory
- **Robust error handling**: Proper validation and cleanup

## Requirements

- `curl` (with HTTPS support)
- Standard Unix tools: `grep`, `sed`, `diff`, `wc`
- Internet connection

## Usage

```bash
./claude_docs_downloader.sh              # Download all documentation
./claude_docs_downloader.sh --keep-temp  # Keep temp files for debugging
./claude_docs_downloader.sh --help       # Show help
./claude_docs_downloader.sh --version    # Show version
```

## Output Structure

```
claude-docs-downloader/
├── claude_docs_downloader.sh
├── claude-code-docs/         # Downloaded documentation
│   ├── overview.md
│   ├── quickstart.md
│   └── ... (30+ files)
└── reports/                  # Change reports
    └── changes_2025-08-13_09-15-30.txt
```

## Troubleshooting

**Connection issues**: Check internet connection and try again  
**Permission errors**: Ensure write permissions in current directory  
**Missing curl**: Install curl package for your system

For debugging, use `--keep-temp` to preserve temporary files.

## License

MIT License - see [LICENSE](LICENSE) file for details.
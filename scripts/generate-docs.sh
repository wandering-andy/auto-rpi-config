#!/bin/bash
set -euo pipefail

## @script Documentation Generator
## @brief Generates README.md and DEVELOPERS.md from module annotations
## @description Parses ## @ tags from lib/*.sh files to build user and developer documentation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly ROOT_DIR
LIB_DIR="${ROOT_DIR}/lib"
readonly LIB_DIR
README_FILE="${ROOT_DIR}/README.md"
readonly README_FILE
DEVELOPERS_FILE="${ROOT_DIR}/DEVELOPERS.md"
readonly DEVELOPERS_FILE

## @fn extract_annotation
## @brief Extract a specific annotation from a file
## @param file Path to the file
## @param tag Annotation tag (e.g., "module", "brief", "description")
## @param multi Allow multiple matches (default: false)
extract_annotation() {
    local file="$1"
    local tag="$2"
    local multi="${3:-false}"
    
    if [[ "$multi" == "true" ]]; then
        grep "^## @${tag}" "$file" 2>/dev/null | sed "s/^## @${tag} //" || true
    else
        grep -m1 "^## @${tag}" "$file" 2>/dev/null | sed "s/^## @${tag} //" || true
    fi
}

## @fn extract_module_info
## @brief Extract documentation from a module file
## @param module_file Path to the module file
extract_module_info() {
    local file="$1"
    local name
    name="$(basename "$file" .sh)"
    
    # Extract module-level annotations
    local module_name brief description author version since
    module_name="$(extract_annotation "$file" "module")"
    brief="$(extract_annotation "$file" "brief")"
    description="$(extract_annotation "$file" "description")"
    author="$(extract_annotation "$file" "author")"
    version="$(extract_annotation "$file" "version")"
    since="$(extract_annotation "$file" "since")"
    
    # Fallback to filename if no module name
    [[ -z "$module_name" ]] && module_name="$name"
    
    # Output module header
    echo "### ${name}.sh"
    echo
    if [[ -n "$module_name" && "$module_name" != "$name" ]]; then
        echo "**Module:** ${module_name}"
        echo
    fi
    if [[ -n "$brief" ]]; then
        echo "${brief}"
        echo
    fi
    if [[ -n "$description" ]]; then
        echo "${description}"
        echo
    fi
    
    # Metadata table
    if [[ -n "$version" || -n "$since" || -n "$author" ]]; then
        echo "| Property | Value |"
        echo "|----------|-------|"
        [[ -n "$version" ]] && echo "| Version | ${version} |"
        [[ -n "$since" ]] && echo "| Since | ${since} |"
        [[ -n "$author" ]] && echo "| Author | ${author} |"
        echo
    fi
    
    # Extract configuration keys
    extract_config_keys "$file"
    
    # Extract public functions
    extract_functions "$file"
    
    # Extract examples if present
    extract_examples "$file"
    
    # Extract notes/warnings
    extract_notes "$file"
}

## @fn extract_config_keys
## @brief Extract CONFIG array usage from module
## @param file Path to the module file
extract_config_keys() {
    local file="$1"
    local config_keys
    
    # Find unique CONFIG[...] references
    config_keys="$(grep -oE 'CONFIG\[[^]]+\]' "$file" 2>/dev/null | \
                   sed 's/CONFIG\[\([^]]*\)\]/\1/' | \
                   sort -u || true)"
    
    if [[ -n "$config_keys" ]]; then
        echo "**Configuration Keys:**"
        echo
        while IFS= read -r key; do
            # Try to find inline documentation for this key
            local key_doc
            key_doc="$(grep -E "CONFIG\[${key}\].*#" "$file" 2>/dev/null | \
                       sed -E 's/.*# (.+)/\1/' | head -1 || true)"
            
            if [[ -n "$key_doc" ]]; then
                echo "- \`${key}\` - ${key_doc}"
            else
                echo "- \`${key}\`"
            fi
        done <<< "$config_keys"
        echo
    fi
}

## @fn extract_functions
## @brief Extract documented functions from module
## @param file Path to the module file
extract_functions() {
    local file="$1"
    local in_func=false
    local func_name func_brief func_desc func_params func_returns func_example
    
    echo "**Functions:**"
    echo
    
    # Parse function documentation
    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]@fn[[:space:]](.+)$ ]]; then
            # Start of new function doc
            [[ -n "$func_name" ]] && output_function_doc
            func_name="${BASH_REMATCH[1]}"
            func_brief=""
            func_desc=""
            func_params=()
            func_returns=""
            func_example=""
        elif [[ "$line" =~ ^##[[:space:]]@brief[[:space:]](.+)$ ]]; then
            func_brief="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^##[[:space:]]@description[[:space:]](.+)$ ]]; then
            func_desc="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^##[[:space:]]@param[[:space:]](.+)$ ]]; then
            func_params+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^##[[:space:]]@return[[:space:]](.+)$ ]]; then
            func_returns="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^##[[:space:]]@example[[:space:]](.+)$ ]]; then
            func_example="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[^#] ]] && [[ -n "$func_name" ]]; then
            # End of function doc block
            output_function_doc
            func_name=""
        fi
    done < "$file"
    
    # Output last function if exists
    [[ -n "$func_name" ]] && output_function_doc
    echo
}

## @fn output_function_doc
## @brief Output formatted function documentation
## @internal
output_function_doc() {
    [[ -z "$func_name" ]] && return
    
    echo "<details>"
    echo "<summary><code>${func_name}</code>"
    [[ -n "$func_brief" ]] && echo " - ${func_brief}"
    echo "</summary>"
    echo
    [[ -n "$func_desc" ]] && echo "${func_desc}"
    [[ -n "$func_desc" ]] && echo
    
    if [[ ${#func_params[@]} -gt 0 ]]; then
        echo "**Parameters:**"
        for param in "${func_params[@]}"; do
            echo "- ${param}"
        done
        echo
    fi
    
    [[ -n "$func_returns" ]] && echo "**Returns:** ${func_returns}" && echo
    [[ -n "$func_example" ]] && echo "**Example:** \`${func_example}\`" && echo
    
    echo "</details>"
    echo
}

## @fn extract_examples
## @brief Extract usage examples from module
## @param file Path to the module file
extract_examples() {
    local file="$1"
    local examples
    examples="$(extract_annotation "$file" "example" "true")"
    
    if [[ -n "$examples" ]]; then
        echo "**Examples:**"
        echo
        echo '```bash'
        echo "$examples"
        echo '```'
        echo
    fi
}

## @fn extract_notes
## @brief Extract notes and warnings from module
## @param file Path to the module file
extract_notes() {
    local file="$1"
    
    # Notes
    local notes
    notes="$(extract_annotation "$file" "note" "true")"
    if [[ -n "$notes" ]]; then
        echo "> **Note:** ${notes}"
        echo
    fi
    
    # Warnings
    local warnings
    warnings="$(extract_annotation "$file" "warning" "true")"
    if [[ -n "$warnings" ]]; then
        echo "> ⚠️ **Warning:** ${warnings}"
        echo
    fi
    
    # See also
    local see_also
    see_also="$(extract_annotation "$file" "see" "true")"
    if [[ -n "$see_also" ]]; then
        echo "**See also:** ${see_also}"
        echo
    fi
}

## @fn extract_module_summary
## @brief Extract brief summary for README
## @param module_file Path to the module file
extract_module_summary() {
    local file="$1"
    local name
    name="$(basename "$file" .sh)"
    
    local module_name brief
    module_name="$(extract_annotation "$file" "module")"
    brief="$(extract_annotation "$file" "brief")"
    
    [[ -z "$module_name" ]] && module_name="$name"
    
    echo "- **${name}** - ${brief:-${module_name}}"
}

## @fn generate_readme
## @brief Generate user-focused README.md
generate_readme() {
    {
        echo "# auto-rpi-config"
        echo
        echo "Automated Raspberry Pi OS configuration system"
        echo
        echo "## Overview"
        echo
        echo "Idempotent, modular configuration system for Raspberry Pi OS Lite (Debian Trixie)."
        echo "Designed for headless deployment with fail-safe defaults and comprehensive error handling."
        echo
        echo "## Quick Start"
        echo
        echo '```bash'
        echo "# 1. Clone and configure"
        echo "git clone <repo-url>"
        echo "cd auto-rpi-config"
        echo "cp config.yml.example config.yml"
        echo "nano config.yml  # Edit for your Pi"
        echo
        echo "# 2. Validate configuration"
        echo "./tests/validate-config.sh config.yml"
        echo
        echo "# 3. Run configuration (as root)"
        echo "sudo ./auto-rpi-config.sh"
        echo
        echo "# 4. Check system health"
        echo "./health-check.sh"
        echo '```'
        echo
        echo "## Features"
        echo
        echo "- Idempotent - Safe to re-run multiple times"
        echo "- Modular - Enable only what you need via YAML"
        echo "- Container support - Podman, Docker, K3s"
        echo "- 3D Printing - OctoPrint, Klipper/Fluidd, OrcaSlicer, Manyfold"
        echo "- Security hardening - SSH key-only, auto-updates"
        echo "- NVMe optimizations - For Raspberry Pi 5"
        echo "- Health monitoring - System status checks"
        echo
        echo "## Available Modules"
        echo
        
        # List core first
        if [[ -f "${LIB_DIR}/core.sh" ]]; then
            extract_module_summary "${LIB_DIR}/core.sh"
        fi
        
        # Then all others alphabetically
        local modules=()
        mapfile -t modules < <(find "$LIB_DIR" -maxdepth 1 -type f -name '*.sh' ! -name 'core.sh' | sort)
        for module in "${modules[@]}"; do
            extract_module_summary "$module"
        done
        
        echo
        echo "See [DEVELOPERS.md](DEVELOPERS.md) for detailed module documentation."
        echo
        echo "## Configuration Examples"
        echo
        echo "### Minimal Headless Server"
        echo '```yaml'
        echo "hostname: pi-server"
        echo "username: admin"
        echo "timezone: America/New_York"
        echo "locale: en_US.UTF-8"
        echo "container_runtime: podman"
        echo '```'
        echo
        echo "### 3D Printer Host"
        echo '```yaml'
        echo "hostname: octoprint-pi"
        echo "container_runtime: docker"
        echo "3dprinter_services: \"octoprint,orcaslicer\""
        echo '```'
        echo
        echo "### Klipper with Fluidd"
        echo '```yaml'
        echo "hostname: klipper-pi"
        echo "container_runtime: none"
        echo "3dprinter_services: \"fluidd\""
        echo '```'
        echo
        echo "See \`config.yml.example\` for all available options."
        echo
        echo "## Development"
        echo
        echo '```bash'
        echo "make lint        # ShellCheck linting"
        echo "make test        # Validate config.yml.example"
        echo "make docs        # Regenerate documentation"
        echo "make permissions # Fix file permissions"
        echo '```'
        echo
        echo "See [DEVELOPERS.md](DEVELOPERS.md) for contribution guidelines."
        echo
        echo "## License"
        echo
        echo "GNU General Public License v3.0"
        echo
        echo "---"
        echo
        echo "*Last updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')*"
    } > "$README_FILE"
    
    echo "Generated: $README_FILE"
}

## @fn generate_developers
## @brief Generate developer-focused DEVELOPERS.md
generate_developers() {
    {
        echo "# Developer Documentation"
        echo
        echo "Technical reference for auto-rpi-config module development and maintenance."
        echo
        echo "## Table of Contents"
        echo
        echo "- [Architecture](#architecture)"
        echo "- [Module Reference](#module-reference)"
        echo "- [Development Standards](#development-standards)"
        echo "- [Testing](#testing)"
        echo "- [Contributing](#contributing)"
        echo
        echo "## Architecture"
        echo
        echo "### Project Structure"
        echo
        echo '```'
        echo "auto-rpi-config/"
        echo "├── auto-rpi-config.sh    # Main orchestrator"
        echo "├── config.yml.example    # Configuration template"
        echo "├── health-check.sh       # System health check"
        echo "├── lib/                  # Configuration modules"
        echo "│   ├── core.sh          # Core functions"
        echo "│   ├── 3dprinter.sh     # 3D printer services"
        echo "│   └── *.sh             # Other modules"
        echo "├── tests/                # Validation & tests"
        echo "│   ├── validate-config.sh"
        echo "│   └── test-module.sh"
        echo "├── scripts/              # Build utilities"
        echo "│   └── generate-docs.sh"
        echo "└── Makefile              # Development commands"
        echo '```'
        echo
        echo "### Module Pattern"
        echo
        echo "Each module in \`lib/\` exports a \`modulename::configure\` function:"
        echo
        echo '```bash'
        echo "#!/bin/bash"
        echo "set -euo pipefail"
        echo
        echo "## @module Module Name"
        echo "## @brief One-line description"
        echo "## @description Detailed explanation"
        echo
        echo "modulename::configure() {"
        echo "    # Idempotency check"
        echo "    [[ -f /var/lib/rpi-config/state/module_done ]] && return 0"
        echo "    "
        echo "    # Configuration logic"
        echo "    some_command || { log_error \"Failed\"; return 1; }"
        echo "    "
        echo "    # Mark complete"
        echo "    mkdir -p /var/lib/rpi-config/state"
        echo "    touch /var/lib/rpi-config/state/module_done"
        echo "}"
        echo '```'
        echo
        echo "## Module Reference"
        echo
        
        # Core first
        if [[ -f "${LIB_DIR}/core.sh" ]]; then
            extract_module_info "${LIB_DIR}/core.sh"
            echo "---"
            echo
        fi
        
        # Then all others alphabetically
        local modules=()
        mapfile -t modules < <(find "$LIB_DIR" -maxdepth 1 -type f -name '*.sh' ! -name 'core.sh' | sort)
        for module in "${modules[@]}"; do
            extract_module_info "$module"
            echo "---"
            echo
        done
        
        echo "## Development Standards"
        echo
        echo "### Required Patterns"
        echo
        echo "- Quote all variables: \`\"\$variable\"\`"
        echo "- Use arrays for lists (never space-separated iteration)"
        echo "- Local function variables: \`local var=\"value\"\`"
        echo "- Return codes: 0 (success) or 1+ (failure)"
        echo "- ShellCheck clean (suppressions in \`.shellcheckrc\` only)"
        echo "- Use \`core.sh\` logging: \`log_step\`, \`log_info\`, \`log_error\`, \`log_success\`"
        echo
        echo "### Annotation Tags"
        echo
        echo "**Module-level:**"
        echo "- \`@module\` - Human-readable module name"
        echo "- \`@brief\` - One-line summary"
        echo "- \`@description\` - Detailed explanation"
        echo "- \`@version\` - Version number"
        echo "- \`@since\` - First release date/version"
        echo "- \`@author\` - Author information"
        echo "- \`@warning\` - Important warnings"
        echo "- \`@note\` - Additional notes"
        echo "- \`@see\` - Related documentation links"
        echo "- \`@example\` - Usage examples"
        echo
        echo "**Function-level:**"
        echo "- \`@fn\` - Function name"
        echo "- \`@brief\` - One-line summary"
        echo "- \`@description\` - Detailed explanation"
        echo "- \`@param\` - Parameter description (can have multiple)"
        echo "- \`@return\` - Return value description"
        echo "- \`@example\` - Usage example"
        echo
        echo "### Error Handling"
        echo
        echo '```bash'
        echo "# Backup before modifying"
        echo "cp /etc/config /etc/config.bak"
        echo
        echo "# Attempt change"
        echo "sed -i 's/old/new/' /etc/config || {"
        echo "    mv /etc/config.bak /etc/config"
        echo "    log_error \"Configuration failed\""
        echo "    return 1"
        echo "}"
        echo
        echo "# Validate"
        echo "validate_command || {"
        echo "    mv /etc/config.bak /etc/config"
        echo "    return 1"
        echo "}"
        echo
        echo "# Cleanup on success"
        echo "rm -f /etc/config.bak"
        echo '```'
        echo
        echo "## Testing"
        echo
        echo "### Linting"
        echo
        echo '```bash'
        echo "make lint  # Run ShellCheck on all scripts"
        echo '```'
        echo
        echo "### Config Validation"
        echo
        echo '```bash'
        echo "./tests/validate-config.sh config.yml"
        echo '```'
        echo
        echo "### Module Testing"
        echo
        echo '```bash'
        echo "make test-module MODULE=3dprinter"
        echo '```'
        echo
        echo "## Contributing"
        echo
        echo "### Branch Strategy"
        echo
        echo "- Branch names: \`feature/<module>\`, \`fix/<area>\`, \`chore/<task>\`"
        echo "- Conventional commits:"
        echo "  - \`feat(containers): add K3s worker join support\`"
        echo "  - \`fix(nvme): correct temperature parsing\`"
        echo "  - \`chore(ci): update ShellCheck version\`"
        echo
        echo "### Pre-Commit Checklist"
        echo
        echo "- [ ] Preserve idempotency (state files, checks)"
        echo "- [ ] Maintain error handling (rollback on failure)"
        echo "- [ ] Update function documentation (\`@fn\`, \`@brief\`)"
        echo "- [ ] Run \`make lint\` (must pass ShellCheck)"
        echo "- [ ] Run \`make test\` (config validation)"
        echo "- [ ] Update \`config.yml.example\` if adding settings"
        echo "- [ ] Run \`make docs\` to regenerate documentation"
        echo
        echo "---"
        echo
        echo "*Documentation auto-generated from module annotations.*"
        echo "*Last updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')*"
    } > "$DEVELOPERS_FILE"
    
    echo "Generated: $DEVELOPERS_FILE"
}

## @fn main
## @brief Generate both README and DEVELOPERS documentation
main() {
    echo "Generating documentation..."
    generate_readme
    generate_developers
    echo "Documentation complete!"
    echo "  User docs: README.md"
    echo "  Developer docs: DEVELOPERS.md"
    echo "  Modules documented: $(find "$LIB_DIR" -name '*.sh' | wc -l)"
}

main "$@"

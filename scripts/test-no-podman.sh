#!/bin/bash
# No-Podman Testing Script
# Tests what we can without requiring Podman/container runtime
# Useful for development on macOS or environments without container support

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Test configuration files syntax
test_configuration_syntax() {
    log "Testing configuration file syntax..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Test YAML files
    for yaml_file in config/*.yml config/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                success "YAML syntax valid: $(basename "$yaml_file")"
                ((tests_passed++))
            else
                error "YAML syntax invalid: $(basename "$yaml_file")"
                ((tests_failed++))
            fi
        fi
    done
    
    # Test Python scripts syntax
    for py_file in code/*.py; do
        if [[ -f "$py_file" ]]; then
            if python3 -m py_compile "$py_file" 2>/dev/null; then
                success "Python syntax valid: $(basename "$py_file")"
                ((tests_passed++))
            else
                error "Python syntax invalid: $(basename "$py_file")"
                ((tests_failed++))
            fi
        fi
    done
    
    # Test shell scripts syntax
    for sh_file in scripts/*.sh; do
        if [[ -f "$sh_file" ]]; then
            if bash -n "$sh_file" 2>/dev/null; then
                success "Shell script syntax valid: $(basename "$sh_file")"
                ((tests_passed++))
            else
                error "Shell script syntax invalid: $(basename "$sh_file")"
                ((tests_failed++))
            fi
        fi
    done
    
    echo "Configuration syntax tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test Python dependencies (what we can without container)
test_python_dependencies() {
    log "Testing Python dependencies availability..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Test basic imports that should work on most systems
    local python_modules=("yaml" "json" "re" "time" "logging" "datetime" "os" "sys")
    
    for module in "${python_modules[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            success "Python module available: $module"
            ((tests_passed++))
        else
            warning "Python module not available: $module"
            ((tests_failed++))
        fi
    done
    
    # Test if requirements.txt is readable
    if [[ -f "config/requirements.txt" ]]; then
        if grep -E "^[a-zA-Z0-9_-]+[=><]" config/requirements.txt >/dev/null; then
            success "Requirements.txt format valid"
            ((tests_passed++))
        else
            error "Requirements.txt format invalid"
            ((tests_failed++))
        fi
    fi
    
    echo "Python dependency tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test systemd configuration syntax
test_systemd_syntax() {
    log "Testing systemd configuration syntax..."
    
    local tests_passed=0
    local tests_failed=0
    
    for container_file in systemd/*.container; do
        if [[ -f "$container_file" ]]; then
            # Check required sections
            if grep -q "^\[Unit\]" "$container_file" && \
               grep -q "^\[Container\]" "$container_file" && \
               grep -q "^\[Install\]" "$container_file"; then
                success "Systemd container syntax valid: $(basename "$container_file")"
                ((tests_passed++))
            else
                error "Systemd container syntax invalid: $(basename "$container_file")"
                ((tests_failed++))
            fi
        fi
    done
    
    for unit_file in systemd/*.unit; do
        if [[ -f "$unit_file" ]]; then
            # Basic unit file validation
            if grep -q "^\[Unit\]" "$unit_file"; then
                success "Systemd unit syntax valid: $(basename "$unit_file")"
                ((tests_passed++))
            else
                error "Systemd unit syntax invalid: $(basename "$unit_file")"
                ((tests_failed++))
            fi
        fi
    done
    
    echo "Systemd syntax tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test file structure and organization
test_file_structure() {
    log "Testing file structure and organization..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Check required directories exist
    local required_dirs=("code" "config" "containerfiles" "scripts" "systemd")
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            success "Required directory exists: $dir/"
            ((tests_passed++))
        else
            error "Missing required directory: $dir/"
            ((tests_failed++))
        fi
    done
    
    # Check required files exist
    local required_files=(
        "containerfiles/fitlet.Containerfile"
        "containerfiles/kiln-ocr.Containerfile"
        "systemd/frigate.container"
        "systemd/mosquitto.container"
        "systemd/kiln-ocr.container"
        "config/frigate.yml"
        "config/mosquitto.conf"
        "config/requirements.txt"
        "code/ocr-processor.py"
        "code/frigate-ocr-integration.py"
        "code/temperature-logger.py"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            success "Required file exists: $file"
            ((tests_passed++))
        else
            error "Missing required file: $file"
            ((tests_failed++))
        fi
    done
    
    echo "File structure tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test Containerfile syntax
test_containerfile_syntax() {
    log "Testing Containerfile syntax..."
    
    local tests_passed=0
    local tests_failed=0
    
    for containerfile in containerfiles/*.Containerfile; do
        if [[ -f "$containerfile" ]]; then
            # Check if it starts with FROM
            if head -n 20 "$containerfile" | grep -q "^FROM "; then
                success "Containerfile syntax valid: $(basename "$containerfile")"
                ((tests_passed++))
            else
                error "Containerfile syntax invalid (no FROM): $(basename "$containerfile")"
                ((tests_failed++))
            fi
            
            # Check for required COPY commands are using proper paths
            local copy_errors=0
            while IFS= read -r line; do
                if [[ $line =~ ^COPY[[:space:]]+\./([^[:space:]]+) ]]; then
                    local source_path="${BASH_REMATCH[1]}"
                    if [[ ! -e "$source_path" && ! -d "$(dirname "$source_path")" ]]; then
                        warning "COPY source may not exist: $source_path in $(basename "$containerfile")"
                        ((copy_errors++))
                    fi
                fi
            done < "$containerfile"
            
            if [[ $copy_errors -eq 0 ]]; then
                success "COPY paths look valid in $(basename "$containerfile")"
                ((tests_passed++))
            else
                warning "Some COPY paths may be invalid in $(basename "$containerfile")"
                ((tests_failed++))
            fi
        fi
    done
    
    echo "Containerfile tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test documentation completeness
test_documentation() {
    log "Testing documentation completeness..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Check required documentation files
    local doc_files=("README.md" "TROUBLESHOOTING.md" "OCR-CONFIGURATION.md" "todo.md")
    
    for doc in "${doc_files[@]}"; do
        if [[ -f "$doc" ]]; then
            success "Documentation exists: $doc"
            ((tests_passed++))
        else
            error "Missing documentation: $doc"
            ((tests_failed++))
        fi
    done
    
    # Check if README has key sections
    if [[ -f "README.md" ]]; then
        local required_sections=("Installation" "Configuration" "Testing" "Usage")
        
        for section in "${required_sections[@]}"; do
            if grep -q "# $section\|## $section" README.md; then
                success "README section exists: $section"
                ((tests_passed++))
            else
                warning "README section missing: $section"
                ((tests_failed++))
            fi
        done
    fi
    
    echo "Documentation tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Main test runner
main() {
    echo "🧪 No-Podman Testing Suite"
    echo "=========================="
    log "Testing project without container runtime dependencies"
    echo ""
    
    local total_passed=0
    local total_failed=0
    
    # Run test categories
    local tests=(
        "test_file_structure"
        "test_configuration_syntax"
        "test_python_dependencies"
        "test_systemd_syntax"
        "test_containerfile_syntax"
        "test_documentation"
    )
    
    for test in "${tests[@]}"; do
        echo "---"
        if $test; then
            ((total_passed++))
        else
            ((total_failed++))
        fi
        echo ""
    done
    
    # Summary
    echo "=========================="
    log "Test Summary"
    success "Test categories passed: $total_passed"
    
    if [[ $total_failed -gt 0 ]]; then
        error "Test categories failed: $total_failed"
        echo ""
        warning "Some non-container tests failed. Review and fix before deployment."
        echo ""
        echo "To run container tests on a Linux system:"
        echo "  ./scripts/test-ocr-container.sh"
        return 1
    else
        echo ""
        success "🎉 All non-container tests passed!"
        echo ""
        echo "Next steps:"
        echo "1. Run container tests on Linux system: ./scripts/test-ocr-container.sh"
        echo "2. Test with actual kiln display images"
        echo "3. Deploy to Fitlet2 device"
        return 0
    fi
}

# Show help
show_help() {
    echo "No-Podman Testing Script"
    echo ""
    echo "Tests project structure, syntax, and configuration without requiring"
    echo "container runtime (Podman/Docker). Useful for development on macOS."
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help"
    echo ""
    echo "Tests performed:"
    echo "  - File structure and organization"
    echo "  - Configuration file syntax (YAML, Python, Shell)"
    echo "  - Python dependency definitions"
    echo "  - Systemd service configuration"
    echo "  - Containerfile syntax"
    echo "  - Documentation completeness"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac 
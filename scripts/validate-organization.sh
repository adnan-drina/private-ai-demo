#!/bin/bash
#
# Project Organization Validation Script
# Purpose: Verify project structure follows ORGANIZATION-RULES.md
# Usage: ./scripts/validate-organization.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Project Organization Validation${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "Project: private-ai-demo"
echo "Date: $(date +%Y-%m-%d)"
echo "Rules: docs/01-ARCHITECTURE/ORGANIZATION-RULES.md"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "   ${YELLOW}→ Suggestion: $2${NC}"
    fi
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "   ${YELLOW}→ Consider: $2${NC}"
    fi
    ((WARN_COUNT++))
}

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================
# CHECK 1: Root Directory Cleanliness
# ============================================
section "1. Root Directory Structure"

# Allowed files in root
ALLOWED_ROOT_FILES=(
    "README.md"
    "env.template"
    ".gitignore"
    ".git"
)

# Allowed directories in root
ALLOWED_ROOT_DIRS=(
    "docs"
    "gitops"
    "stages"
    "scripts"
    ".git"
)

# Check for unexpected files in root
echo "Checking root directory..."
ROOT_VIOLATION=0

for item in *; do
    if [ -f "$item" ]; then
        ALLOWED=0
        for allowed_file in "${ALLOWED_ROOT_FILES[@]}"; do
            if [ "$item" = "$allowed_file" ]; then
                ALLOWED=1
                break
            fi
        done
        if [ $ALLOWED -eq 0 ]; then
            fail "Unexpected file in root: $item" "Move to appropriate directory per ORGANIZATION-RULES.md"
            ROOT_VIOLATION=1
        fi
    elif [ -d "$item" ]; then
        ALLOWED=0
        for allowed_dir in "${ALLOWED_ROOT_DIRS[@]}"; do
            if [ "$item" = "$allowed_dir" ]; then
                ALLOWED=1
                break
            fi
        done
        if [ $ALLOWED -eq 0 ]; then
            fail "Unexpected directory in root: $item" "Review if this should be organized elsewhere"
            ROOT_VIOLATION=1
        fi
    fi
done

if [ $ROOT_VIOLATION -eq 0 ]; then
    pass "Root directory contains only allowed files and directories"
fi

# ============================================
# CHECK 2: Misplaced Documentation
# ============================================
section "2. Documentation Organization"

# Check for .md files in root (except README.md)
echo "Checking for misplaced documentation..."
MISPLACED_DOCS=0

for md_file in *.md; do
    if [ -f "$md_file" ] && [ "$md_file" != "README.md" ]; then
        fail "Documentation file in root: $md_file" "Move to docs/ with appropriate category"
        MISPLACED_DOCS=1
    fi
done

if [ $MISPLACED_DOCS -eq 0 ]; then
    pass "No misplaced documentation files in root"
fi

# Check for docs directory structure
if [ -d "docs" ]; then
    pass "docs/ directory exists"
    
    # Check for expected category directories
    EXPECTED_CATEGORIES=(
        "docs/01-ARCHITECTURE"
        "docs/02-PIPELINES"
        "docs/03-CONFIGURATION"
        "docs/03-WORKBENCH"
        "docs/archive"
    )
    
    for category in "${EXPECTED_CATEGORIES[@]}"; do
        if [ -d "$category" ]; then
            pass "Category directory exists: $category"
        else
            warn "Missing category directory: $category" "Create if needed"
        fi
    done
else
    fail "docs/ directory does not exist" "Create docs/ directory structure"
fi

# ============================================
# CHECK 3: Misplaced Kubernetes Manifests
# ============================================
section "3. Kubernetes Manifests Organization"

# Check for .yaml files in root
echo "Checking for misplaced Kubernetes manifests..."
MISPLACED_YAML=0

for yaml_file in *.yaml *.yml; do
    if [ -f "$yaml_file" ]; then
        fail "YAML manifest in root: $yaml_file" "Move to appropriate gitops/stageXX-*/ directory"
        MISPLACED_YAML=1
    fi
done

if [ $MISPLACED_YAML -eq 0 ]; then
    pass "No YAML manifests in root directory"
fi

# Check for gitops directory structure
if [ -d "gitops" ]; then
    pass "gitops/ directory exists"
    
    # Check for expected stage directories
    EXPECTED_STAGES=(
        "gitops/argocd"
        "gitops/stage00-ai-platform"
        "gitops/stage01-model-serving"
        "gitops/stage02-model-alignment"
        "gitops/stage03-model-monitoring"
        "gitops/stage04-model-integration"
    )
    
    for stage in "${EXPECTED_STAGES[@]}"; do
        if [ -d "$stage" ]; then
            pass "Stage directory exists: $stage"
        else
            warn "Missing stage directory: $stage" "Create if deploying this stage"
        fi
    done
else
    fail "gitops/ directory does not exist" "Create gitops/ directory structure"
fi

# ============================================
# CHECK 4: Misplaced Scripts
# ============================================
section "4. Scripts Organization"

# Check for .sh files in root
echo "Checking for misplaced scripts..."
MISPLACED_SCRIPTS=0

for script in *.sh; do
    if [ -f "$script" ]; then
        fail "Script in root: $script" "Move to stages/stageX-*/ or scripts/"
        MISPLACED_SCRIPTS=1
    fi
done

if [ $MISPLACED_SCRIPTS -eq 0 ]; then
    pass "No scripts in root directory"
fi

# Check stages directory
if [ -d "stages" ]; then
    pass "stages/ directory exists"
    
    EXPECTED_STAGE_DIRS=(
        "stages/stage0-ai-platform"
        "stages/stage1-model-serving"
        "stages/stage2-model-alignment"
        "stages/stage3-model-monitoring"
        "stages/stage4-model-integration"
    )
    
    for stage_dir in "${EXPECTED_STAGE_DIRS[@]}"; do
        if [ -d "$stage_dir" ]; then
            pass "Stage directory exists: $stage_dir"
        else
            warn "Missing stage directory: $stage_dir"
        fi
    done
else
    warn "stages/ directory does not exist" "Create if needed"
fi

# Check scripts directory
if [ -d "scripts" ]; then
    pass "scripts/ directory exists for utilities"
else
    warn "scripts/ directory does not exist" "Create for project-wide utility scripts"
fi

# ============================================
# CHECK 5: Dated Documents Detection
# ============================================
section "5. Dated Documents (Archive Candidates)"

# Find documents with date patterns (YYYY-MM-DD)
echo "Checking for dated documents that may need archiving..."
DATED_DOCS_FOUND=0

if [ -d "docs" ]; then
    # Look for files with date patterns in docs/ (excluding archive/)
    while IFS= read -r -d '' dated_file; do
        # Skip if already in archive
        if [[ "$dated_file" == *"/archive/"* ]]; then
            continue
        fi
        
        # Extract filename without path
        filename=$(basename "$dated_file")
        
        # Check if file has date pattern (YYYY-MM-DD)
        if [[ "$filename" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            warn "Dated document found: $dated_file" "Consider archiving to docs/archive/YYYY-MM/"
            DATED_DOCS_FOUND=1
        fi
    done < <(find docs -type f -name "*.md" -print0 2>/dev/null)
fi

if [ $DATED_DOCS_FOUND -eq 0 ]; then
    pass "No dated documents found outside archive/"
fi

# ============================================
# CHECK 6: Backup Files Detection
# ============================================
section "6. Backup and Temporary Files"

# Check for backup files
echo "Checking for backup and temporary files..."
BACKUP_FILES_FOUND=0

for pattern in "*.bak" "*.bak2" "*.bak3" "*.backup" "*.old" ".tmp-*"; do
    while IFS= read -r -d '' backup_file; do
        # Skip .git directory
        if [[ "$backup_file" == *"/.git/"* ]]; then
            continue
        fi
        warn "Backup/temp file found: $backup_file" "Delete after confirming changes work"
        BACKUP_FILES_FOUND=1
    done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
done

if [ $BACKUP_FILES_FOUND -eq 0 ]; then
    pass "No backup or temporary files found"
fi

# ============================================
# CHECK 7: Documentation in Archive Has READMEs
# ============================================
section "7. Archive Documentation"

if [ -d "docs/archive" ]; then
    echo "Checking archive directories for READMEs..."
    MISSING_ARCHIVE_README=0
    
    # Find all directories in archive (depth 2: docs/archive/YYYY-MM/)
    while IFS= read -r -d '' archive_dir; do
        if [ ! -f "$archive_dir/README.md" ]; then
            warn "Archive directory missing README: $archive_dir" "Create README explaining what's archived and why"
            MISSING_ARCHIVE_README=1
        fi
    done < <(find docs/archive -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null)
    
    if [ $MISSING_ARCHIVE_README -eq 0 ]; then
        pass "All archive directories have READMEs"
    fi
else
    pass "No archive directory yet (will be created when needed)"
fi

# ============================================
# CHECK 8: .gitignore Verification
# ============================================
section "8. .gitignore Configuration"

if [ -f ".gitignore" ]; then
    pass ".gitignore file exists"
    
    # Check for essential exclusions
    ESSENTIAL_PATTERNS=(
        "docs/"
        "**/.env"
        "**/*.log"
        ".cursor"
        "*.plan.md"
    )
    
    for pattern in "${ESSENTIAL_PATTERNS[@]}"; do
        if grep -q "$pattern" .gitignore; then
            pass ".gitignore excludes: $pattern"
        else
            warn ".gitignore missing pattern: $pattern" "Add to .gitignore"
        fi
    done
else
    fail ".gitignore file does not exist" "Create .gitignore"
fi

# ============================================
# Summary
# ============================================
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${GREEN}✅ Passed: $PASS_COUNT${NC}"
echo -e "${RED}❌ Failed: $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARN_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}🎉 Project organization is compliant!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Project has organization issues that need to be fixed.${NC}"
    echo ""
    echo "Review the failures above and:"
    echo "1. Check docs/01-ARCHITECTURE/ORGANIZATION-RULES.md for placement rules"
    echo "2. Move files to correct locations"
    echo "3. Run this script again to verify"
    echo ""
    exit 1
fi


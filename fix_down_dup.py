#!/usr/bin/env python3
"""Clean up the down section to have exactly one data cleanup with correct indentation."""

with open('fablo-x.sh', 'r') as f:
    content = f.read()

# Fix the down section: remove the duplicate inserted after network rm
# and keep only the one after restore_backups (with correct indentation)
old_down = '''    docker network rm fabric_test 2>/dev/null || true

        echo "Cleaning FSC node data from previous runs..."
        for node in $NODES; do
            rm -rf "$FABRIC_X_DIR/conf/$node/data" 2>/dev/null || true
        done

    echo "Restoring original configurations..."
    restore_backups

    echo "Cleaning FSC node data..."
    for node in $NODES; do
        rm -rf "$FABRIC_X_DIR/conf/$node/data" 2>/dev/null || true
    done
    echo "✅ Fabric-X network is DOWN (original configs restored)"'''

new_down = '''    docker network rm fabric_test 2>/dev/null || true

    echo "Restoring original configurations..."
    restore_backups

    echo "Cleaning FSC node data..."
    for node in $NODES; do
        rm -rf "$FABRIC_X_DIR/conf/$node/data" 2>/dev/null || true
    done
    echo "✅ Fabric-X network is DOWN (original configs restored)"'''

content = content.replace(old_down, new_down)

with open('fablo-x.sh', 'w', newline='\n') as f:
    f.write(content)

print('Done - removed duplicate cleanup in down section')

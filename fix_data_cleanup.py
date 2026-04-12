#!/usr/bin/env python3
"""Add FSC node data cleanup to fablo-fabricx.sh teardown."""

with open('fablo-fabricx.sh', 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    new_lines.append(line)

    # After each "docker network rm fabric_test" in the cleanup (up command), add data cleanup
    if 'docker network rm fabric_test' in line and i > 0:
        # Check if we're in the "up" command cleanup or the "down" command
        # Add FSC data cleanup after network removal
        new_lines.append('\n')
        new_lines.append('        echo "Cleaning FSC node data from previous runs..."\n')
        new_lines.append('        for node in $NODES; do\n')
        new_lines.append('            rm -rf "$FABRIC_X_DIR/conf/$node/data" 2>/dev/null || true\n')
        new_lines.append('        done\n')

    # After restore_backups in the "down" command, add data cleanup
    if ('restore_backups' in line and
        i > 0 and
        any('Restoring original' in lines[j] for j in range(max(0, i-3), i))):
        new_lines.append('\n')
        new_lines.append('    echo "Cleaning FSC node data..."\n')
        new_lines.append('    for node in $NODES; do\n')
        new_lines.append('        rm -rf "$FABRIC_X_DIR/conf/$node/data" 2>/dev/null || true\n')
        new_lines.append('    done\n')

with open('fablo-fabricx.sh', 'w', newline='\n') as f:
    f.writelines(new_lines)

print('Done - added FSC data cleanup to both up-cleanup and down')

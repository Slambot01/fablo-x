#!/usr/bin/env python3
"""Fix trap in fablo-fabricx.sh: disable trap on successful up/down completion."""

with open('fablo-fabricx.sh', 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    # Remove the global trap line - we'll add targeted traps instead
    if line.strip() == "trap 'restore_backups 2>/dev/null' EXIT":
        continue
    if line.strip() == '# Safety: restore .bak files on script interruption (Ctrl+C, errors)':
        continue

    new_lines.append(line)

# Now find the deploy section in "up" and add trap there, then clear after success
final_lines = []
for i, line in enumerate(new_lines):
    final_lines.append(line)

    # After "Configurations deployed" line, add trap
    if '✅ Configurations deployed' in line:
        final_lines.append('\n')
        final_lines.append('    # Safety: if script is interrupted after deploy, restore originals\n')
        final_lines.append("    trap 'restore_backups 2>/dev/null' INT TERM\n")

    # Before the final success message, clear the trap
    if 'Fabric-X network is UP and ready' in line:
        # Insert trap clear before this line
        final_lines.insert(-1, '    # Configs deployed successfully — disable safety restore\n')
        final_lines.insert(-1, '    trap - INT TERM\n')
        final_lines.insert(-1, '\n')

with open('fablo-fabricx.sh', 'w', newline='\n') as f:
    f.writelines(final_lines)

print('Done - trap fixed to only fire on interruption, not normal exit')

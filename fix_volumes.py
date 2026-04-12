#!/usr/bin/env python3
"""Fix docker compose down commands to include -v flag for volume cleanup."""

with open('fablo-fabricx.sh', 'r') as f:
    content = f.read()

# Fix all 4 "docker compose ... down" commands to add -v flag
# Lines 88, 89 (cleanup in up), 174, 175 (down command)
content = content.replace(
    'docker compose -f compose.yml -f compose-endorser2.yml down 2>/dev/null || true',
    'docker compose -f compose.yml -f compose-endorser2.yml down -v 2>/dev/null || true'
)
content = content.replace(
    'docker compose -f compose-xdev.yml down 2>/dev/null || true',
    'docker compose -f compose-xdev.yml down -v 2>/dev/null || true'
)

with open('fablo-fabricx.sh', 'w', newline='\n') as f:
    f.write(content)

print('Done - added -v flag to all docker compose down commands')

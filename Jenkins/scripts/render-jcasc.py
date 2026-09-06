#!/usr/bin/env python3
# Renders jcasc/jenkins.yaml into a plain, self-contained YAML document by
# inlining every `<key>: !include <file>` line as a literal block scalar.
#
# Why this exists: JCasC's built-in `!include` custom YAML tag turned out to
# be rejected outright by the configuration-as-code/snakeyaml-api plugin
# versions resolved for this project (org.yaml.snakeyaml.error.YAMLException:
# Invalid tag: !include) - a plugin-version compatibility issue, not a syntax
# mistake. Rather than pin exact plugin versions to chase a working
# combination (already abandoned once for the base plugin set - see
# plugins.txt), the source files stay split for readability (jenkins.yaml,
# the two agent pod templates, the Job DSL script) and this script splices
# them together into the one flat YAML document JCasC actually has to parse.
import os
import re
import sys

if len(sys.argv) != 2:
    print("usage: render-jcasc.py <path-to-jcasc/jenkins.yaml>", file=sys.stderr)
    sys.exit(1)

src = sys.argv[1]
# !include basenames are written assuming the flattened ConfigMap layout
# (jcasc/jenkins.yaml, agent-pods/*, jobs/* all end up as flat sibling keys
# in casc_configs/), so search across the repo's actual subdirectories
# rather than only next to jenkins.yaml itself.
jenkins_dir = os.path.dirname(os.path.dirname(os.path.abspath(src)))
search_dirs = [
    os.path.dirname(os.path.abspath(src)),
    os.path.join(jenkins_dir, "agent-pods"),
    os.path.join(jenkins_dir, "jobs"),
]


def resolve(fname):
    for d in search_dirs:
        candidate = os.path.join(d, fname)
        if os.path.isfile(candidate):
            return candidate
    raise FileNotFoundError(f"{fname} not found in any of {search_dirs}")

include_re = re.compile(r'^(?P<indent>[ \t]*)(?P<key>\S.*?): !include (?P<file>\S+)\s*$')

out_lines = []
with open(src) as f:
    for line in f:
        line = line.rstrip('\n')
        m = include_re.match(line)
        if not m:
            out_lines.append(line)
            continue
        indent = m.group('indent')
        key = m.group('key')
        fname = m.group('file')
        out_lines.append(f"{indent}{key}: |")
        content_indent = indent + "    "
        inc_path = resolve(fname)
        with open(inc_path) as inc:
            for iline in inc:
                iline = iline.rstrip('\n')
                out_lines.append(content_indent + iline if iline.strip() else "")

print("\n".join(out_lines))

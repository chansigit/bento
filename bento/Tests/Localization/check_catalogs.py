"""Validate the shipped catalogs, source lookups, and format argument contracts."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
expected = {'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'es', 'vi', 'sv', 'ru', 'nb', 'fi', 'de', 'it', 'uk', 'sw', 'pt-BR'}

def read_strings(path):
    result = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");', line)
        assert match, (path, line)
        key, value = map(json.loads, match.groups())
        assert key not in result and value, (path, key)
        result[key] = value
    return result

catalogs = {p.parent.stem: read_strings(p) for p in (root / 'Resources').glob('*.lproj/Localizable.strings')}
assert set(catalogs) == expected
base = catalogs['zh-Hans']
for language, catalog in catalogs.items():
    assert catalog.keys() == base.keys(), language
    for key, value in catalog.items():
        assert re.findall(r'%(?:@|.)', key) == re.findall(r'%(?:@|.)', value), (language, key)
    info = read_strings(root / 'Resources' / (language + '.lproj') / 'InfoPlist.strings')
    assert set(info) == {'NSLocationWhenInUseUsageDescription', 'NSLocationUsageDescription'}

for source in (root / 'Sources').glob('*.swift'):
    for match in re.finditer(r'L\(("(?:\\.|[^"\\])*")', source.read_text()):
        literal = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), match[1])
        assert json.loads(literal) in base, (source, literal)
print(f'Localization catalogs passed: {len(catalogs)} languages × {len(base)} strings, format arguments and source keys')

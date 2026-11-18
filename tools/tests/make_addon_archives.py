"""Deterministic small ZIP corpus; no downloaded add-ons or user files."""
import pathlib
import stat
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

def archive(name, entries, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(root / (name + '.zip'), 'w', compression=compression) as out:
        for path, data in entries:
            out.writestr(path, data)

toc = b'## Interface: 16001\n## Title: WolkaraForever Fixture\n## Version: 1\nmain.lua\n'
archive('valid', [('Fixture/', b''), ('Fixture/Fixture.toc', toc), ('Fixture/main.lua', b'-- fixture\n')])
archive('nested', [('Wrapper/Fixture/Fixture.toc', toc)])
for name, path in [('traversal', '../outside'), ('absolute', '/outside'), ('double', 'Fixture//file'),
                   ('dot', 'Fixture/./file'), ('colon', 'Fixture/a:b'), ('control', 'Fixture/a\nb')]:
    archive(name, [(path, b'bad')])
archive('case', [('Fixture/a', b'a'), ('Fixture/A', b'b')])
archive('unicode', [('Fixture/caf\u00e9', b'a'), ('Fixture/cafe\u0301', b'b')])
link = zipfile.ZipInfo('Fixture/link')
link.create_system = 3
link.external_attr = (stat.S_IFLNK | 0o777) << 16
archive('symlink', [(link, b'../../outside')])
archive('corrupt', [('Fixture/Fixture.toc', toc)], zipfile.ZIP_STORED)
path = root / 'corrupt.zip'
# Flip one byte of the stored entry's data: the archive stays structurally valid and
# the length is unchanged, so the CRC is the thing that must be refused. Replacing a
# word with a different-length one would shift every offset after it, which makes the
# fixture depend on the length of whatever text the entry happens to carry.
data = bytearray(path.read_bytes())
data[data.index(toc)] ^= 0xFF
path.write_bytes(data)
(root / 'invalid.zip').write_bytes(b'not a zip')
archive('file-directory', [('Fixture/a', b'file'), ('Fixture/a/b', b'child')])

archive('oversized-file', [('Fixture/large', b'0' * (64 * 1024 * 1024 + 1))])
archive('too-many', [(f'Fixture/{i}', b'') for i in range(20_001)])

# An entry whose mode says FIFO. ZIPFoundation cannot see it as anything but an ordinary
# file, so what must land on disk is a regular file with the entry's bytes in it - never a
# FIFO, which would block any later reader of that tree for ever. The test asserts that.
fifo = zipfile.ZipInfo('Fixture/fifo')
fifo.create_system = 3
fifo.external_attr = (stat.S_IFIFO | 0o644) << 16
archive('special-file', [('Fixture/Fixture.toc', toc), (fifo, b'not a fifo\n')])

# A deflate entry whose *declared* uncompressed size is a lie, which is the case the
# declared-size checks cannot catch: the compressed size is truthful, so the stream is read
# to its end and expands to 70 MiB while every declared-size check sees ten bytes. Built by
# rewriting the uncompressed-size field of the entry's central directory record (name length
# 2 + extra 2 + comment 2 + disk 2 + internal 2 + external 4 + offset 4 + crc 4 + compressed
# 4 = 24 bytes in).
archive('lying-size', [('Fixture/large', b'0' * (70 * 1024 * 1024))])
path = root / 'lying-size.zip'
data = bytearray(path.read_bytes())
central = data.find(b'PK\x01\x02')
assert central >= 0, 'the central directory record was not where it was expected'
data[central + 24:central + 28] = (10).to_bytes(4, 'little')
path.write_bytes(bytes(data))

# Updates can replace the original top-level folder and carry a companion addon.
archive('renamed-update', [('Replacement/Replacement.toc', toc.replace(b'Version: 1', b'Version: 2')),
                           ('Companion/Companion.toc', toc)])
archive('multi-flavor', [('Flavors/A_Classic.toc', toc),
                         ('Flavors/Z_Mainline.toc', toc.replace(b'16001', b'120005'))])

# Database add-ons can carry their data in huge TOCs (QuestieDB uses ~15 MiB).
# The installer reads bounded metadata but must copy every byte of both flavors.
database_toc = (b'## Interface: 16001\n## Title: Database fixture\n## Version: 1\n'
                + b'## X-Data: ' + b'x' * (15 * 1024 * 1024) + b'\nmain.lua\n')
archive('database-toc', [('Database/Database_Forever.toc', database_toc),
                         ('Database/Database_Camelot.toc', database_toc),
                         ('Database/main.lua', b'-- fixture\n')])

# A real-world multi-client package uses a generic error placeholder, while the
# selected game's suffix has its actual title/version. Never display the stub.
archive('flavor', [
    ('Flavor/Flavor.toc', b'## Interface: 00000\n## Title: game client not supported\n'),
    ('Flavor/Flavor_Forever.toc', b'## Interface: 16001\n## Title: Forever quests\n## Version: 12\n'),
    ('Flavor/Flavor_Camelot.toc', b'## Interface: 16001\n## Title: Legacy quests\n## Version: 11\n'),
    ('Flavor/Flavor_Vanilla.toc', b'## Interface: 11509\n## Title: Era quests\n## Version: 10\n'),
])

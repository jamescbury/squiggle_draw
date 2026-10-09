#!/usr/bin/env python3
"""Fail closed on private artifacts in a source checkout; no network or mutations."""
from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
allowed_samples={'shell.png','apple.png','pear_and_pitcher.png','mountain_lake.png'}
allowed_gallery={f'{subject}-{style}.png' for subject in ('shell','apple','pear_and_pitcher','mountain_lake') for style in ('source','form','circular','circular-fine','circular-round','circular-uniform','continuous','hatching','stipple','poly')}
media={'.png','.jpg','.jpeg','.heic','.gif','.tiff','.webp','.mp4','.mov','.pdf'}
ignored={'.git','.build','.gradle','.gradle-home','build','dist','__pycache__'}
failures=[];count=0
for p in root.rglob('*'):
    rel=p.relative_to(root)
    if any(part in ignored for part in rel.parts) or not p.is_file(): continue
    count+=1
    if p.is_symlink(): failures.append(f'symlink: {rel}')
    if re.search(r'IMG_\d|DSC_\d|family|portrait|before-update',str(rel),re.I): failures.append(f'unapproved file: {rel}')
    if p.name=='local.properties' or p.name.startswith('.env') or p.suffix.lower() in {'.jks','.keystore','.p12','.pem','.key','.apk','.zip'}: failures.append(f'local/binary artifact: {rel}')
    if p.suffix.lower() in media:
        approved=(str(rel).startswith('squiggle-draw/Sources/SquiggleDraw/Resources/Samples/') and p.name in allowed_samples) or (str(rel).startswith('docs/gallery/') and p.name in allowed_gallery)
        if not approved: failures.append(f'unapproved media: {rel}')
    if p.suffix.lower() in {'.swift','.java','.md','.yml','.yaml','.json','.html','.gradle','.properties','.sh','.py','.txt','.env'}:
        text=p.read_text(errors='replace')
        if re.search(r'/' + r'Users/[^/\s]+/|IMG_\d{4}|http://(?:\d{1,3}\.){3}\d{1,3}:\d+/[a-f0-9]{64}',text): failures.append(f'private path or pairing address: {rel}')
if failures:
    print('\n'.join(failures));sys.exit(1)
print(f'Publication check passed: {count} files; media limited to the approved generated samples/gallery.')

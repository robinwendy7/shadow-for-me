"""SCD schema-1 records, including bounded chunk transport used since diary 1.1."""
import json
import zlib
from pathlib import Path

LIMIT = 8 * 1024 * 1024

def iter_records(path, stats=None):
    stats = stats if stats is not None else {}
    stats.setdefault('invalid', 0)
    groups = {}
    with Path(path).open(encoding='utf-8-sig', errors='replace') as stream:
        for line in stream:
            if '[SCD] ' in line:
                raw = line.split('[SCD] ', 1)[1]
            elif line.lstrip().startswith('{'):
                raw = line
            else:
                continue
            try:
                value = json.loads(raw)
                if not isinstance(value, dict) or value.get('schema') != 1 or not isinstance(value.get('kind'), str):
                    continue
                if value.get('kind') != 'record_chunk':
                    yield value
                    continue
                session, seq = value['session'], value['seq']
                index, count = value['chunk_index'], value['chunk_count']
                data, checksum = value['data'], value['checksum']
                if (value.get('encoding') != 'hex-adler32-v1' or not isinstance(session, str)
                    or not isinstance(seq, int) or not isinstance(index, int) or not isinstance(count, int)
                    or not 1 <= index <= count <= 8389 or not isinstance(data, str) or len(data) > 2000
                    or len(data) % 2 or not isinstance(checksum, str) or len(checksum) != 8):
                    raise ValueError('invalid chunk header')
                bytes.fromhex(data)
                key = (session, seq)
                if key not in groups:
                    if len(groups) >= 32:
                        groups.pop(next(iter(groups)))
                        stats['invalid'] += 1
                    groups[key] = {'count': count, 'checksum': checksum, 'parts': {}}
                group = groups[key]
                if group['count'] != count or group['checksum'] != checksum:
                    groups.pop(key, None)
                    raise ValueError('conflicting chunk group')
                old = group['parts'].get(index)
                if old is not None and old != data:
                    groups.pop(key, None)
                    raise ValueError('conflicting duplicate chunk')
                group['parts'][index] = data
                if len(group['parts']) != count:
                    continue
                groups.pop(key)
                payload = bytes.fromhex(''.join(group['parts'][i] for i in range(1, count + 1)))
                if len(payload) > LIMIT or f'{zlib.adler32(payload):08x}' != checksum:
                    raise ValueError('chunk checksum mismatch')
                record = json.loads(payload.decode('utf-8'))
                if (not isinstance(record, dict) or record.get('schema') != 1
                    or record.get('session') != session or record.get('seq') != seq
                    or record.get('kind') == 'record_chunk'):
                    raise ValueError('reconstructed identity mismatch')
                yield record
            except (ValueError, KeyError, TypeError, UnicodeError):
                stats['invalid'] += 1
    stats['incomplete'] = len(groups)

import { crc32, deflateRawSync, inflateRawSync } from "node:zlib";

/**
 * The small part of the ZIP format that Office files need: stored and deflated entries, no encryption,
 * no ZIP64. Kept in-house so the Office tools add no dependency.
 */

const EOCD = 0x06054b50;
const CENTRAL = 0x02014b50;
const LOCAL = 0x04034b50;

export class ZipArchive {
  private readonly entries = new Map<string, { method: number; compressedSize: number; size: number; localOffset: number }>();

  constructor(private readonly buf: Buffer) {
    let eocd = -1;
    for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
      if (buf.readUInt32LE(i) === EOCD) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw new Error("not a ZIP file (no end-of-central-directory record)");
    const count = buf.readUInt16LE(eocd + 10);
    let p = buf.readUInt32LE(eocd + 16);
    if (count === 0xffff || p === 0xffffffff) throw new Error("ZIP64 archives are not supported");
    for (let i = 0; i < count; i++) {
      if (buf.readUInt32LE(p) !== CENTRAL) throw new Error("corrupt ZIP central directory");
      const flags = buf.readUInt16LE(p + 8);
      if (flags & 0x1) throw new Error("encrypted ZIP entries are not supported (is the document password-protected?)");
      const nameLen = buf.readUInt16LE(p + 28);
      const extraLen = buf.readUInt16LE(p + 30);
      const commentLen = buf.readUInt16LE(p + 32);
      const name = buf.toString("utf8", p + 46, p + 46 + nameLen);
      this.entries.set(name, {
        method: buf.readUInt16LE(p + 10),
        compressedSize: buf.readUInt32LE(p + 20),
        size: buf.readUInt32LE(p + 24),
        localOffset: buf.readUInt32LE(p + 42),
      });
      p += 46 + nameLen + extraLen + commentLen;
    }
  }

  names(): string[] {
    return [...this.entries.keys()];
  }

  has(name: string): boolean {
    return this.entries.has(name);
  }

  read(name: string): Buffer {
    const e = this.entries.get(name);
    if (!e) throw new Error(`the archive has no entry "${name}"`);
    const p = e.localOffset;
    if (this.buf.readUInt32LE(p) !== LOCAL) throw new Error(`corrupt ZIP local header for "${name}"`);
    const start = p + 30 + this.buf.readUInt16LE(p + 26) + this.buf.readUInt16LE(p + 28);
    const data = this.buf.subarray(start, start + e.compressedSize);
    if (e.method === 0) return Buffer.from(data);
    if (e.method === 8) return inflateRawSync(data);
    throw new Error(`unsupported ZIP compression method ${e.method} for "${name}"`);
  }

  text(name: string): string {
    return this.read(name).toString("utf8");
  }
}

export function writeZip(files: readonly { readonly name: string; readonly data: Buffer | string }[]): Buffer {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const file of files) {
    const raw = typeof file.data === "string" ? Buffer.from(file.data, "utf8") : file.data;
    const name = Buffer.from(file.name, "utf8");
    const deflated = deflateRawSync(raw);
    const stored = deflated.length >= raw.length;
    const data = stored ? raw : deflated;
    const crc = crc32(raw);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(LOCAL, 0);
    header.writeUInt16LE(20, 4); // version needed
    header.writeUInt16LE(0x0800, 6); // UTF-8 names
    header.writeUInt16LE(stored ? 0 : 8, 8);
    header.writeUInt16LE(0, 10); // time
    header.writeUInt16LE(0x21, 12); // date: 1980-01-01
    header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(data.length, 18);
    header.writeUInt32LE(raw.length, 22);
    header.writeUInt16LE(name.length, 26);
    header.writeUInt16LE(0, 28);
    locals.push(header, name, data);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(CENTRAL, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(stored ? 0 : 8, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(0x21, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += 30 + name.length + data.length;
  }
  const centralSize = centrals.reduce((n, b) => n + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(EOCD, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, ...centrals, end]);
}

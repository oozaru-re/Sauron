#import <Foundation/Foundation.h>
#import <zlib.h>

void printBanner(void) {
    printf("\n");
    printf("   _____                             \n");
    printf("  / ____|                            \n");
    printf(" | (___   __ _ _   _ _ __ ___  _ __  \n");
    printf("  \\___ \\ / _` | | | | '__/ _ \\| '_ \\ \n");
    printf("  ____) | (_| | |_| | | | (_) | | | |\n");
    printf(" |_____/ \\__,_|\\__,_|_|  \\___/|_| |_|\n");
    printf("\n");
    printf("   Sauron — Stego Tool for PDF\n");
    printf("   Created by Oozaru\n");
    printf("   GitHub: https://github.com/oozaru-re\n");
    printf("\n");
}


@interface PDFStreamExtractor : NSObject
- (instancetype)initWithData:(NSData *)data;
- (BOOL)validatePDF;
- (void)extractToCurrentDirectory;
@end

@implementation PDFStreamExtractor {
    NSData *_pdf;
}

- (instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        _pdf = data;
    }
    return self;
}

- (BOOL)validatePDF {
    if (!_pdf || _pdf.length < 4) {
        printf("[-] Too short or not a PDF\n");
        exit(1);
    }
    const unsigned char *b = _pdf.bytes;
    NSString *h = [NSString stringWithFormat:@"%02X%02X%02X%02X", b[0], b[1], b[2], b[3]];
    if ([h isEqualToString:@"25504446"]) {
        printf("[+] Valid PDF\n");
        return YES;
    }
    printf("[-] Not a PDF\n");
    exit(1);
}

static NSRange R(NSData *d, NSData *n, NSRange rg) {
    return [d rangeOfData:n options:0 range:rg];
}

static NSString *S(NSData *d, NSRange r) {
    if (r.location == NSNotFound || NSMaxRange(r) > d.length) return nil;
    return [[NSString alloc] initWithData:[d subdataWithRange:r] encoding:NSASCIIStringEncoding];
}

static NSUInteger SK(NSData *d, NSUInteger p) {
    if (p >= d.length) return p;
    const uint8_t *b = d.bytes;
    if (b[p] == '\r') return (p + 1 < d.length && b[p + 1] == '\n') ? p + 2 : p + 1;
    if (b[p] == '\n') return p + 1;
    return p;
}

static NSString *DictBefore(NSData *pdf, NSUInteger streamPos) {
    if (streamPos == 0) return nil;
    const uint8_t *bytes = pdf.bytes;
    NSInteger i = (NSInteger)streamPos - 1;
    NSInteger st = -1, en = -1;

    for (; i >= 1; i--) {
        if (bytes[i - 1] == '<' && bytes[i] == '<') {
            st = i - 1;
            break;
        }
    }
    if (st < 0) return nil;

    for (NSUInteger j = st + 2; j + 1 < streamPos; j++) {
        if (bytes[j] == '>' && bytes[j + 1] == '>') {
            en = (NSInteger)j + 2;
            break;
        }
    }
    if (en < 0) return nil;

    return S(pdf, NSMakeRange((NSUInteger)st, (NSUInteger)(en - st)));
}

static NSNumber *LenFromDict(NSString *dict) {
    if (!dict) return nil;

    NSRange r = [dict rangeOfString:@"/Length"];
    if (r.location == NSNotFound) return nil;

    NSString *t = [dict substringFromIndex:NSMaxRange(r)];
    NSScanner *sc = [NSScanner scannerWithString:t];
    [sc scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];

    if ([t containsString:@" R"]) return nil;

    double v;
    if ([sc scanDouble:&v] && v >= 0) {
        return @((NSUInteger)v);
    }
    return nil;
}

static NSArray<NSString *> *Filters(NSString *dict) {
    if (!dict) return @[];

    NSRange r = [dict rangeOfString:@"/Filter"];
    if (r.location == NSNotFound) return @[];

    NSString *t = [dict substringFromIndex:NSMaxRange(r)];
    NSScanner *sc = [NSScanner scannerWithString:t];
    [sc scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];

    NSMutableArray *fs = [NSMutableArray array];

    if ([sc scanString:@"[" intoString:NULL]) {
        while (!sc.atEnd) {
            [sc scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
            if ([sc scanString:@"]" intoString:NULL]) break;

            if ([sc scanString:@"/" intoString:NULL]) {
                NSString *name;
                [sc scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@" /]\r\n\t"]
                                   intoString:&name];
                if (name) [fs addObject:name];
            } else {
                [sc scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@" /]\r\n\t"]
                                   intoString:NULL];
            }
        }
    } else if ([sc scanString:@"/" intoString:NULL]) {
        NSString *name;
        [sc scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&name];
        if (name) [fs addObject:name];
    }

    return fs;
}

static NSData *InflateFlate(NSData *compressed) {
    if (!compressed || compressed.length == 0) return nil;

    NSMutableData *decomp = [NSMutableData dataWithLength:compressed.length * 4];
    z_stream strm = {0};
    strm.next_in = (Bytef *)compressed.bytes;
    strm.avail_in = (uInt)compressed.length;

    if (inflateInit(&strm) != Z_OK) return nil;

    int status;
    do {
        if (strm.total_out >= decomp.length) {
            [decomp increaseLengthBy:compressed.length];
        }
        strm.next_out = [decomp mutableBytes] + strm.total_out;
        strm.avail_out = (uInt)(decomp.length - strm.total_out);
        status = inflate(&strm, Z_SYNC_FLUSH);
    } while (status == Z_OK);

    inflateEnd(&strm);

    if (status != Z_STREAM_END) return nil;

    [decomp setLength:strm.total_out];
    return decomp;
}

static NSData *ASCII85(NSData *in) {
    if (!in || in.length == 0) return NSData.data;

    const uint8_t *p = in.bytes;
    const uint8_t *e = p + in.length;
    NSMutableData *o = NSMutableData.data;
    uint32_t t = 0;
    int c = 0;

    while (p < e) {
        uint8_t ch = *p++;
        if (ch == '~') { if (p < e && *p == '>') p++; break; }
        if (ch <= ' ') continue;
        if (ch == 'z') { if (c != 0) return nil; uint32_t z = 0; [o appendBytes:&z length:4]; continue; }
        if (ch < '!' || ch > 'u') return nil;

        t = t * 85 + (ch - '!');
        c++;

        if (c == 5) {
            uint32_t v = t;
            uint8_t b[4] = { (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF };
            [o appendBytes:b length:4];
            t = 0;
            c = 0;
        }
    }

    if (c > 0) {
        for (int i = c; i < 5; i++) t = t * 85 + 84;
        uint32_t v = t;
        uint8_t b[4] = { (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF };
        [o appendBytes:b length:(c - 1)];
    }

    return o;
}

static NSData *ASCIIHex(NSData *in) {
    if (!in || in.length == 0) return NSData.data;

    const uint8_t *p = in.bytes;
    const uint8_t *e = p + in.length;
    NSMutableData *o = NSMutableData.data;
    int n = -1;

    while (p < e) {
        uint8_t ch = *p++;
        if (ch == '>') break;
        if (ch <= ' ') continue;

        int v = -1;
        if (ch >= '0' && ch <= '9') v = ch - '0';
        else if (ch >= 'A' && ch <= 'F') v = ch - 'A' + 10;
        else if (ch >= 'a' && ch <= 'f') v = ch - 'a' + 10;
        else return nil;

        if (n < 0) {
            n = v;
        } else {
            uint8_t byte = (uint8_t)((n << 4) | v);
            [o appendBytes:&byte length:1];
            n = -1;
        }
    }

    if (n >= 0) {
        uint8_t byte = (uint8_t)(n << 4);
        [o appendBytes:&byte length:1];
    }

    return o;
}

static NSData *Decode(NSData *d, NSString *f) {
    if ([f isEqualToString:@"ASCII85Decode"]) return ASCII85(d);
    if ([f isEqualToString:@"ASCIIHexDecode"]) return ASCIIHex(d);
    if ([f isEqualToString:@"FlateDecode"])    return InflateFlate(d);
    return nil;
}

static NSData *Apply(NSData *p, NSArray<NSString *> *fs) {
    NSData *cur = p;
    for (NSString *f in fs) {
        NSData *n = Decode(cur, f);
        if (!n) return nil;
        cur = n;
    }
    return cur;
}

- (void)extractToCurrentDirectory {
    NSData *ts = [@"stream" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *te = [@"endstream" dataUsingEncoding:NSASCIIStringEncoding];

    NSUInteger loc = 0;
    NSUInteger idx = 0;

    while (loc < _pdf.length) {
        NSRange sr = NSMakeRange(loc, _pdf.length - loc);
        NSRange rs = R(_pdf, ts, sr);
        if (rs.location == NSNotFound) break;

        NSString *dict = DictBefore(_pdf, rs.location);
        NSArray  *fs   = Filters(dict);
        NSNumber *len  = LenFromDict(dict);

        NSUInteger start = SK(_pdf, NSMaxRange(rs));

        NSRange pr = {0, 0};
        if (len && start + len.unsignedIntegerValue <= _pdf.length) {
            pr = NSMakeRange(start, len.unsignedIntegerValue);
        }
        if (pr.length == 0) {
            NSRange es = NSMakeRange(start, _pdf.length - start);
            NSRange re = R(_pdf, te, es);
            if (re.location == NSNotFound || re.location <= start) {
                loc = NSMaxRange(rs);
                continue;
            }
            pr = NSMakeRange(start, re.location - start);
        }

        NSData *raw = [_pdf subdataWithRange:pr];
        NSData *dec = fs.count ? Apply(raw, fs) : raw;

        if (!dec) {
            NSString *filterStr = fs.count ? [fs componentsJoinedByString:@","] : @"none";
            printf("[-] Stream %lu | decode fail | filters: %s | len: %lu\n",
                   (unsigned long)idx,
                   [filterStr UTF8String],
                   (unsigned long)raw.length);
        } else {
            NSString *txt = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
            BOOL js = NO;
            if (txt) {
                NSString *l = txt.lowercaseString;
                js = ([l containsString:@"function"] ||
                      [l containsString:@"eval"] ||
                      [l containsString:@"unescape("] ||
                      [l containsString:@"/javascript"] ||
                      [l containsString:@"var "]);
            }

            NSString *ext = js ? @"js" : (txt ? @"txt" : @"bin");
            NSString *fname = [NSString stringWithFormat:@"stream_%03lu.%@",
                               (unsigned long)idx, ext];
            [dec writeToFile:fname atomically:YES];

            NSString *filterStr = fs.count ? [fs componentsJoinedByString:@","] : @"none";
            printf("[+] Stream %lu | filters: %s | %lu → %lu bytes | saved: %s\n",
                   (unsigned long)idx,
                   [filterStr UTF8String],
                   (unsigned long)raw.length,
                   (unsigned long)dec.length,
                   [fname UTF8String]);

            if (txt) {
                NSString *pv = [txt stringByReplacingOccurrencesOfString:@"\r" withString:@""];
                if (pv.length > 240) {
                    pv = [[pv substringToIndex:240] stringByAppendingString:@"…"];
                }
                printf("[dump %lu]\n%s\n", (unsigned long)idx, [pv UTF8String]);
            } else {
                printf("[dump %lu] (binary)\n", (unsigned long)idx);
            }
        }

        NSRange ar = NSMakeRange(NSMaxRange(pr), _pdf.length - NSMaxRange(pr));
        NSRange re = R(_pdf, te, ar);
        loc = (re.location != NSNotFound) ? NSMaxRange(re) : NSMaxRange(pr);
        idx++;
    }

    if (idx == 0) {
        printf("[-] No streams found.\n");
    }
}

@end

int main(int argc, const char *argv[]) {
    printBanner();
    if (argc < 2) {
        printf("Usage: %s <pdf_path>\n", argv[0]);
        return 1;
    }
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    NSData *pdf = [NSData dataWithContentsOfFile:path];

    PDFStreamExtractor *ex = [[PDFStreamExtractor alloc] initWithData:pdf];
    [ex validatePDF];
    [ex extractToCurrentDirectory];

    return 0;
}

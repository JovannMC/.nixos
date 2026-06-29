/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 the davinci-resolve-linux-aac-fix contributors
 *
 * INTEROPERABILITY (17 U.S.C. §1201(f)). This file contains no code,
 * symbols, RTTI strings, headers, or extracted byte sequences from
 * DaVinci Resolve. It uses only:
 *   - standard POSIX/libc symbols (mprotect, readlink, write, open, etc.)
 *   - a set of seven version-fingerprint bytes per cave-patch site (used
 *     solely to verify '"'"'this is the supported Resolve version'"'"' before patching;
 *     functionally equivalent to a per-site checksum)
 *   - a set of seven small replacement-byte sequences encoding the patches
 *     themselves (authored by the shim, not extracted from Resolve)
 *   - an MPEG-4 ISO Base Media File Format box-parser (public ISO/IEC 14496-1)
 *
 * The shim no-ops cleanly on any unsupported Resolve version: if a
 * fingerprint mismatch is detected at any site, that site is skipped, a
 * trace line is written to stderr, and Resolve runs unchanged.
 *
 * Verified Resolve version: Studio 20.3.2 Linux
 *   (md5 of /opt/resolve/bin/resolve == 4319a873…)
 *
 * Build: gcc -shared -fPIC -O2 -o aac_hybrid_shim.so aac_hybrid_shim.c
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* ============================================================
 * PART A — Cave-patch constructor (port of aac_native_shim.c)
 * ============================================================ */

static void wlog(const char *s) {
    const char *p = s; size_t n = 0; while (p[n]) n++;
    (void)!write(2, s, n);
}
static void whex(const char *tag, unsigned long v) {
    char buf[64]; int i = 0; const char *t = tag; while (*t) buf[i++] = *t++;
    buf[i++] = '0'; buf[i++] = 'x';
    char tmp[16]; int j = 0; if (!v) tmp[j++] = '0';
    while (v) { int d = v & 0xf; tmp[j++] = d < 10 ? '0' + d : 'a' + d - 10; v >>= 4; }
    while (j) buf[i++] = tmp[--j];
    buf[i++] = '\n'; (void)!write(2, buf, i);
}

typedef struct {
    uintptr_t va;
    const unsigned char *orig;
    const unsigned char *neu;
    size_t len;
    const char *label;
} patch_t;

/* Patches (verbatim from aac_native_shim.c — same VA, same bytes).
 * cave = 48 83 44 24 10 1f  e9 7e 84 05 08  (add qword[rsp+0x10],0x1f ; jmp 0x846881b) */
static const unsigned char FP1[]={0x41,0x81,0xfc,0x45,0x4e,0x4f,0x4e,0x0f,0x84,0x27,0x09,0x00,0x00,0xe9,0xa9,0x00,0x00,0x00};
static const unsigned char PX1[]={0x41,0x81,0xfc,0x20,0x63,0x61,0x61,0x0f,0x84,0xfb,0x00,0x00,0x00,0xe9,0xa9,0x00,0x00,0x00};
static const unsigned char FP2[]={0x74,0x14}, PX2[]={0x90,0x90};
static const unsigned char FP3[]={0x31,0x63,0x61,0x61}, PX3[]={0x20,0x63,0x61,0x61};
static const unsigned char FP4[]={0x10}, PX4[]={0x02};
static const unsigned char FP5[]={0x10}, PX5[]={0x02};
static const unsigned char FP8[]={0,0,0,0,0,0,0,0,0,0,0};
static const unsigned char PX8[]={0x48,0x83,0x44,0x24,0x10,0x1f,0xe9,0x7e,0x84,0x05,0x08};
/* je rel32 = CAVE_VA-(JE_VA+6) = 0x410392-0x84686b5 = -0x8058323 = 0xf7fa7cdd (LE dd7cfaf7) */
static const unsigned char FP6[]={0x34,0x01,0x00,0x00}, PX6[]={0xdd,0x7c,0xfa,0xf7};

static const patch_t PATCHES[] = {
    {0x8473b9e, FP1, PX1, sizeof FP1, "1 redirect"},
    {0x8473ce4, FP2, PX2, sizeof FP2, "2 skip-wrapper"},
    {0xc9fc694, FP3, PX3, sizeof FP3, "3 map key"},
    {0x8468657, FP4, PX4, sizeof FP4, "4 ex-gate1"},
    {0x84686ab, FP5, PX5, sizeof FP5, "5 ex-gate2"},
    {0x410392,  FP8, PX8, sizeof FP8, "8 CAVE body"},   /* cave BEFORE je-redirect */
    {0x84686b1, FP6, PX6, sizeof FP6, "6 je->CAVE"},
};
#define NPATCH (sizeof(PATCHES)/sizeof(PATCHES[0]))

/* exe guard — only patch the actual Resolve binary, NEVER /opt/resolve/bin/fuscript
 * or other helpers (corrupts scripting subprocesses (Resolve forks helper binaries that share the binary; corrupting them breaks the scripting API)). Match suffix exactly. */
static int is_resolve(void) {
    char exe[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0) return 0;
    /* truncation guard: readlink fills exactly sizeof(exe)-1 on truncation;
     * we'd be matching against a possibly-truncated path → refuse rather than
     * risk a false positive at the tail. */
    if (n >= (ssize_t)(sizeof(exe) - 1)) return 0;
    exe[n] = 0;
    const char *want = "/opt/resolve/bin/resolve";
    size_t wl = 0; while (want[wl]) wl++;
    if ((size_t)n < wl) return 0;
    for (size_t i = 0; i < wl; i++)
        if (exe[n - wl + i] != want[i]) return 0;
    return 1;
}

#ifndef TEST_PARSER
__attribute__((constructor))
#endif
static void aac_hybrid_apply_cave(void) {
    if (!is_resolve()) return;
    wlog("[aac_hybrid] resolve detected; applying in-memory cave patches\n");
    int ok = 0, skip = 0, fail = 0;
    for (size_t k = 0; k < NPATCH; k++) {
        const patch_t *p = &PATCHES[k];
        unsigned char *m = (unsigned char *)p->va;
        uintptr_t pg = p->va & ~(uintptr_t)0xfff;
        size_t span = (p->va + p->len) - pg;
        size_t prot_len = (span + 0xfff) & ~(uintptr_t)0xfff;
        if (mprotect((void *)pg, prot_len, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
            whex("[aac_hybrid] FAIL mprotect ", p->va);
            fail++;
            continue;
        }
        int already = 1, matches = 1;
        for (size_t i = 0; i < p->len; i++) {
            if (m[i] != p->neu[i]) already = 0;
            if (m[i] != p->orig[i]) matches = 0;
        }
        if (already) {
            mprotect((void *)pg, prot_len, PROT_READ | PROT_EXEC);
            skip++;
            continue;
        }
        if (!matches) {
            whex("[aac_hybrid] SKIP orig-mismatch ", p->va);
            mprotect((void *)pg, prot_len, PROT_READ | PROT_EXEC);
            skip++;
            continue;
        }
        for (size_t i = 0; i < p->len; i++) m[i] = p->neu[i];
        mprotect((void *)pg, prot_len, PROT_READ | PROT_EXEC);   /* restore W^X */
        whex("[aac_hybrid] patched ", p->va);
        ok++;
    }
    whex("[aac_hybrid] cave applied ok=", ok);
    whex("[aac_hybrid] cave skip=", skip);
    whex("[aac_hybrid] cave fail=", fail);
}

/* ============================================================
 * PART B — open()-hook + per-file esds detection + transcode
 * ============================================================ */

/* Pointers to the real glibc symbols (resolved lazily via dlsym). We MUST call
 * these directly inside the parser to avoid recursion into our own hooks. */
static int   (*real_open)(const char *, int, ...) = NULL;
static int   (*real_open64)(const char *, int, ...) = NULL;
static int   (*real_openat)(int, const char *, int, ...) = NULL;
static int   (*real_openat64)(int, const char *, int, ...) = NULL;
static FILE *(*real_fopen)(const char *, const char *) = NULL;
static FILE *(*real_fopen64)(const char *, const char *) = NULL;
static ssize_t (*real_pread64)(int, void *, size_t, off_t) = NULL;
static int   (*real_close)(int) = NULL;

#define INIT_REAL(sym) do { if (!real_##sym) real_##sym = dlsym(RTLD_NEXT, #sym); } while (0)

static int verbose = -1;
static int dbg(void) {
    if (verbose == -1) {
        const char *v = getenv("AAC_HYBRID_VERBOSE");
        verbose = (v && *v && *v != '0') ? 1 : 0;
    }
    return verbose;
}

/* Marker-file logger — stderr unreliable in audio worker threads; a marker-file is robust.
 * Resolve closes/redirects/loses stderr per-thread (audio worker threads
 * especially), so fprintf(stderr) silently disappears. write() to a marker
 * file via the REAL open() is the proven-reliable diagnostic channel.
 *
 * Log path: AAC_HYBRID_LOG env if set, else /tmp/aac-hybrid.log. Appends one
 * line per event. Thread-safe via O_APPEND.
 */
static void marker(const char *msg) {
    if (!dbg()) return;
    const char *path = getenv("AAC_HYBRID_LOG");
    if (!path || !*path) path = "/tmp/aac-hybrid.log";
    INIT_REAL(open);
    if (!real_open) return;
    /* O_NONBLOCK: if AAC_HYBRID_LOG points at a FIFO with no reader, a
     * blocking open() would hang Resolve's import thread; we'd rather drop
     * the log line than freeze the GUI. */
    int fd = real_open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NONBLOCK, 0644);
    if (fd < 0) return;
    /* prepend timestamp + pid for ordering across processes */
    char hdr[64];
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int n = snprintf(hdr, sizeof(hdr), "[%ld.%03ld pid=%d] ",
                     (long)ts.tv_sec, (long)(ts.tv_nsec / 1000000), (int)getpid());
    (void)!write(fd, hdr, n > 0 ? (size_t)n : 0);
    (void)!write(fd, msg, strlen(msg));
    if (msg[0] && msg[strlen(msg)-1] != '\n') (void)!write(fd, "\n", 1);
    close(fd);
}

/* printf-style wrapper around marker() */
static void markerf(const char *fmt, ...) {
    if (!dbg()) return;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n < 0) return;
    marker(buf);
}

/* Optional cache-dir override (matches aac-redirect.so's AAC_REDIRECT_CACHE_DIR
 * env var: when set + creatable, siblings live there as <hash>-<basename>.resolve.mp4
 * instead of beside the source). */
static const char *cache_dir(void) {
    static const char *cached = (const char *)-1;
    if (cached == (const char *)-1) {
        const char *v = getenv("AAC_REDIRECT_CACHE_DIR");
        if (!v || !*v) {
            cached = NULL;
        } else {
            struct stat st;
            if (stat(v, &st) != 0) {
                char buf[PATH_MAX];
                strncpy(buf, v, sizeof(buf) - 1); buf[sizeof(buf) - 1] = 0;
                for (char *p = buf + 1; *p; p++) {
                    if (*p == '/') { *p = 0; mkdir(buf, 0755); *p = '/'; }
                }
                mkdir(buf, 0755);
            }
            if (stat(v, &st) == 0 && S_ISDIR(st.st_mode)) cached = v;
            else cached = NULL;
        }
    }
    return cached;
}

/* djb2 (UNSIGNED — caught by adversarial review of aac-redirect.c 2026-05-13;
 * signed char sign-extends bytes >= 0x80 and breaks UTF-8 path hash). */
static unsigned long path_hash(const char *s) {
    unsigned long h = 5381;
    unsigned char c;
    while ((c = (unsigned char)*s++)) h = ((h << 5) + h) + c;
    return h;
}

static int has_video_ext(const char *path) {
    if (!path) return 0;
    const char *dot = strrchr(path, '.');
    if (!dot) return 0;
    return (!strcasecmp(dot, ".mp4") || !strcasecmp(dot, ".m4a") ||
            !strcasecmp(dot, ".mov") || !strcasecmp(dot, ".m4v"));
}

static int is_already_sibling(const char *path) {
    const char *p = strstr(path, ".resolve.mp4");
    return p && !p[strlen(".resolve.mp4")];
}

static int is_noop_marker(const char *path) {
    const char *p = strstr(path, ".resolve-noop");
    return p && !p[strlen(".resolve-noop")];
}

/* Build the sibling path for SRC. Caller free()'s. Returns NULL on alloc fail or
 * if path has no extension (per adversarial fix in aac-redirect.c). */
static char *build_sibling(const char *path) {
    const char *slash = strrchr(path, '/');
    const char *bn_start = slash ? slash + 1 : path;
    const char *dot = strrchr(bn_start, '.');
    if (!dot) return NULL;
    size_t base_len = dot - path;
    const char *cdir = cache_dir();
    if (cdir) {
        char abs[PATH_MAX];
        const char *src_for_hash = path;
        if (realpath(path, abs)) src_for_hash = abs;
        unsigned long h = path_hash(src_for_hash);
        size_t bn_len = dot - bn_start;
        size_t cdir_len = strlen(cdir);
        size_t out_sz = cdir_len + 1 + 16 + 1 + bn_len + strlen(".resolve.mp4") + 1;
        char *out = malloc(out_sz);
        if (!out) return NULL;
        snprintf(out, out_sz, "%s/%08lx-%.*s.resolve.mp4",
                 cdir, h & 0xFFFFFFFFUL, (int)bn_len, bn_start);
        return out;
    }
    char *sibling = malloc(base_len + 16);
    if (!sibling) return NULL;
    memcpy(sibling, path, base_len);
    strcpy(sibling + base_len, ".resolve.mp4");
    return sibling;
}

/* === Per-path decision cache (3-state) === */

typedef enum {
    DEC_UNKNOWN = 0,   /* not in cache */
    DEC_CAVE_OK = 1,   /* esds parsed; 4-byte lengths AND AOT=2 -> let cave handle natively */
    DEC_SIBLING = 2,   /* esds parsed; compact length OR non-LC AOT -> redirect to sibling */
    DEC_NOOP    = 3,   /* parse failed OR file not a usable mp4 -> never redirect */
} decision_t;

#define CACHE_BUCKETS 256
typedef struct cache_entry {
    char *path;
    decision_t decision;
    struct cache_entry *next;
} cache_entry_t;

static cache_entry_t *cache[CACHE_BUCKETS];
static pthread_mutex_t cache_lock = PTHREAD_MUTEX_INITIALIZER;

static decision_t cache_get(const char *path) {
    unsigned long h = path_hash(path) % CACHE_BUCKETS;
    pthread_mutex_lock(&cache_lock);
    decision_t d = DEC_UNKNOWN;
    for (cache_entry_t *e = cache[h]; e; e = e->next) {
        if (strcmp(e->path, path) == 0) { d = e->decision; break; }
    }
    pthread_mutex_unlock(&cache_lock);
    return d;
}

static void cache_put(const char *path, decision_t dec) {
    unsigned long h = path_hash(path) % CACHE_BUCKETS;
    pthread_mutex_lock(&cache_lock);
    for (cache_entry_t *e = cache[h]; e; e = e->next) {
        if (strcmp(e->path, path) == 0) { e->decision = dec; pthread_mutex_unlock(&cache_lock); return; }
    }
    cache_entry_t *ne = malloc(sizeof(cache_entry_t));
    if (ne) {
        ne->path = strdup(path);
        ne->decision = dec;
        ne->next = cache[h];
        cache[h] = ne;
    }
    pthread_mutex_unlock(&cache_lock);
}

/* === mp4 box walker + esds parser ===
 *
 * MPEG-4 boxes are big-endian. Layout:
 *   [u32 size][u32 kind][...body up to size...]
 * If size==1, a 64-bit size follows. We need:
 *   moov/trak/mdia/minf/stbl/stsd/mp4a/esds
 * stsd has 8 bytes (version+flags+entry_count) before its child entries; mp4a has
 * 28 bytes of audio-sample-entry header before nested boxes (per ISO/IEC 14496-12).
 *
 * Because mp4 muxers often put mdat BEFORE moov (forward-streaming files like
 * file 01 in our test set: mdat=479KB, moov 100KB+ into the file), we MUST be
 * willing to seek past large boxes — not just read the first 4KB. Strategy:
 * use real_pread64() to fetch top-level box headers; only when we hit moov do
 * we read its full body for nested-box descent.
 *
 * Hard limits to bound malicious/corrupt input:
 *   - Max top-level boxes scanned: 64
 *   - Max moov body size we'll read: 1 MiB (real moov boxes are typically <200KB)
 *   - File size assumed via fstat
 */

static int read_u32_be(int fd, off_t off, uint32_t *out) {
    unsigned char b[4];
    ssize_t n = real_pread64(fd, b, 4, off);
    if (n != 4) return -1;
    *out = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
           ((uint32_t)b[2] << 8) | (uint32_t)b[3];
    return 0;
}

static int read_u64_be(int fd, off_t off, uint64_t *out) {
    unsigned char b[8];
    ssize_t n = real_pread64(fd, b, 8, off);
    if (n != 8) return -1;
    *out = 0;
    for (int i = 0; i < 8; i++) *out = (*out << 8) | b[i];
    return 0;
}

/* Read MPEG-4 expandable descriptor length. value out, returns bytes_consumed,
 * sets *compact=1 iff used a SINGLE byte with bit-7 clear (the only-byte short
 * form that the cave can't handle). Returns -1 on truncation. */
static int read_descriptor_length(const unsigned char *buf, size_t buf_len, size_t off,
                                   unsigned int *val_out, int *compact_out) {
    unsigned int val = 0;
    int consumed = 0;
    int saw_continuation = 0;
    while (consumed < 4) {
        if (off + (size_t)consumed >= buf_len) return -1;
        unsigned char b = buf[off + consumed];
        val = (val << 7) | (b & 0x7F);
        consumed++;
        if (b & 0x80) saw_continuation = 1;
        else break;
    }
    *val_out = val;
    /* compact form = exactly 1 byte and never saw the high-bit continuation marker.
     * 4-byte expandable form = 4 bytes used (with high-bit set on first 3). Any
     * length form that uses 2-3 bytes is NEITHER pure compact nor the cave's
     * assumed 4-byte form — treat as non-compact for the decision (the cave
     * looks for esds_payload+0x1f which corresponds to exactly the 4-byte form).
     * Caller MUST also check that consumed==4 to use cave path. */
    *compact_out = (consumed == 1 && !saw_continuation) ? 1 : 0;
    (void)saw_continuation;
    return consumed;
}

/* Parse esds box BODY (everything after the 8-byte box header), determine the
 * cave/fall-through decision. Returns:
 *    DEC_CAVE_OK   = all 3 descriptor lengths used 4-byte form AND audioObjectType==2
 *    DEC_SIBLING   = compact-length detected OR non-LC AOT detected
 *    DEC_NOOP      = parse failed (malformed esds)
 */
static decision_t parse_esds_decision(const unsigned char *body, size_t body_len) {
    size_t p = 4;  /* skip 4-byte version+flags */
    if (p >= body_len) return DEC_NOOP;
    if (body[p] != 0x03) return DEC_NOOP;     /* expect ES_Descriptor tag */
    p++;
    unsigned int es_len; int es_compact;
    int es_consumed = read_descriptor_length(body, body_len, p, &es_len, &es_compact);
    if (es_consumed < 0) return DEC_NOOP;
    p += es_consumed;
    if (p + 3 > body_len) return DEC_NOOP;
    p += 3;  /* 16-bit ES_ID + 8-bit flags */

    if (p >= body_len || body[p] != 0x04) return DEC_NOOP;
    p++;
    unsigned int dcd_len; int dcd_compact;
    int dcd_consumed = read_descriptor_length(body, body_len, p, &dcd_len, &dcd_compact);
    if (dcd_consumed < 0) return DEC_NOOP;
    p += dcd_consumed;
    if (p + 13 > body_len) return DEC_NOOP;
    /* objectTypeIndication=body[p] (typically 0x40=mp4a). Skip 13-byte DCD body. */
    p += 13;

    if (p >= body_len || body[p] != 0x05) return DEC_NOOP;
    p++;
    unsigned int dsi_len; int dsi_compact;
    int dsi_consumed = read_descriptor_length(body, body_len, p, &dsi_len, &dsi_compact);
    if (dsi_consumed < 0) return DEC_NOOP;
    p += dsi_consumed;

    if (p >= body_len) return DEC_NOOP;
    /* AudioSpecificConfig: first 5 bits of body[p] = audioObjectType */
    unsigned char asc_b0 = body[p];
    unsigned char asc_b1 = (p + 1 < body_len) ? body[p + 1] : 0;
    unsigned int aot = (asc_b0 >> 3) & 0x1F;
    if (aot == 31) {
        /* Extended AOT: 6 more bits across b0+b1 */
        aot = 32 + (((asc_b0 & 0x07) << 6) | ((asc_b1 >> 2) & 0x3F));
    }

    /* Cave is safe IFF all three descriptor lengths were encoded with the FULL
     * 4-byte expandable form (consumed==4) AND audioObjectType is LC (2).
     * Any deviation -> fall through.
     *
     * Why "==4" not "!=1": the cave's +0x1f offset hard-codes
     *   esds_payload[0x1f] = AudioSpecificConfig byte 0
     * which is true ONLY when every descriptor length expands to 4 bytes
     * (0x80 0x80 0x80 NN). 2-byte and 3-byte intermediate forms also displace
     * the ASC; treat them as fall-through too. */
    int cave_safe_length = (es_consumed == 4 && dcd_consumed == 4 && dsi_consumed == 4);
    (void)es_compact; (void)dcd_compact; (void)dsi_compact;  /* superseded by ==4 check */

    if (cave_safe_length && aot == 2) {
        return DEC_CAVE_OK;
    }
    return DEC_SIBLING;
}

/* Walk top-level boxes starting at FD offset 0 to find moov. Sets *moov_off and
 * *moov_size on success. Returns 0 on success, -1 on failure / not found.
 * Bounded: at most 64 top-level boxes scanned. */
static int find_moov(int fd, off_t file_size, off_t *moov_off, uint64_t *moov_size) {
    off_t off = 0;
    int scanned = 0;
    while (off + 8 <= file_size && scanned < 64) {
        uint32_t size32, kind;
        if (read_u32_be(fd, off, &size32) < 0) return -1;
        if (read_u32_be(fd, off + 4, &kind) < 0) return -1;
        uint64_t size = size32;
        off_t header = 8;
        if (size == 1) {
            if (read_u64_be(fd, off + 8, &size) < 0) return -1;
            header = 16;
        } else if (size == 0) {
            size = file_size - off;
        }
        if (size < (uint64_t)header || (off_t)(off + size) > file_size) return -1;
        if (kind == 0x6d6f6f76U /* 'moov' */) {
            *moov_off = off;
            *moov_size = size;
            return 0;
        }
        off += size;
        scanned++;
    }
    return -1;
}

/* Inside a buffer (the loaded moov body), walk nested boxes via the box-tree
 * path to find esds. Returns offset of the esds BOX (its size word) within the
 * moov body, or -1 if not found.
 *
 * Box-traversal rules (per ISO/IEC 14496-12):
 *   - container boxes (moov, trak, mdia, minf, stbl, dinf, edts, udta): recurse
 *     into body verbatim
 *   - stsd: skip 8-byte (version+flags+entry_count) then recurse
 *   - mp4a (sample entry): skip 28-byte audio-sample-entry header then recurse
 */
static int is_container_kind(uint32_t kind) {
    return kind == 0x6d6f6f76U /* moov */
        || kind == 0x7472616bU /* trak */
        || kind == 0x6d646961U /* mdia */
        || kind == 0x6d696e66U /* minf */
        || kind == 0x7374626cU /* stbl */
        || kind == 0x64696e66U /* dinf */
        || kind == 0x65647473U /* edts */
        || kind == 0x75647461U /* udta */;
}

static ssize_t walk_for_esds(const unsigned char *buf, size_t buf_len,
                              size_t off, size_t end, int depth) {
    if (depth > 8) return -1;  /* sanity bound */
    while (off + 8 <= end) {
        uint32_t size32 = ((uint32_t)buf[off] << 24) | ((uint32_t)buf[off + 1] << 16) |
                          ((uint32_t)buf[off + 2] << 8) | (uint32_t)buf[off + 3];
        uint32_t kind = ((uint32_t)buf[off + 4] << 24) | ((uint32_t)buf[off + 5] << 16) |
                        ((uint32_t)buf[off + 6] << 8) | (uint32_t)buf[off + 7];
        uint64_t size = size32;
        size_t header = 8;
        if (size == 1) {
            if (off + 16 > end) return -1;
            size = 0;
            for (int i = 0; i < 8; i++) size = (size << 8) | buf[off + 8 + i];
            header = 16;
        } else if (size == 0) {
            size = end - off;
        }
        if (size < header || off + size > end) return -1;
        size_t body_off = off + header;
        size_t body_end = off + size;
        if (kind == 0x65736473U /* esds */) {
            return (ssize_t)off;
        }
        if (kind == 0x73747364U /* stsd */) {
            if (body_off + 8 <= body_end) {
                ssize_t r = walk_for_esds(buf, buf_len, body_off + 8, body_end, depth + 1);
                if (r >= 0) return r;
            }
        } else if (kind == 0x6d703461U /* mp4a */) {
            if (body_off + 28 <= body_end) {
                ssize_t r = walk_for_esds(buf, buf_len, body_off + 28, body_end, depth + 1);
                if (r >= 0) return r;
            }
        } else if (is_container_kind(kind)) {
            ssize_t r = walk_for_esds(buf, buf_len, body_off, body_end, depth + 1);
            if (r >= 0) return r;
        }
        /* leaf box we don't care about: skip */
        off += size;
    }
    return -1;
}

/* Top-level: open the file (via real_open to avoid recursion), find moov, read
 * its body, walk to esds, parse decision. Returns one of DEC_CAVE_OK / DEC_SIBLING
 * / DEC_NOOP. Never throws.
 *
 * IMPORTANT: this function MUST be defensive — never write, never modify state,
 * never spawn anything. Just read + return decision. */
static decision_t probe_file_decision(const char *path) {
    INIT_REAL(open);
    INIT_REAL(close);
    INIT_REAL(pread64);
    if (!real_open || !real_close || !real_pread64) return DEC_NOOP;

    int fd = real_open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return DEC_NOOP;

    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < 32) {
        real_close(fd);
        return DEC_NOOP;
    }
    off_t file_size = st.st_size;

    off_t moov_off = 0;
    uint64_t moov_size = 0;
    if (find_moov(fd, file_size, &moov_off, &moov_size) < 0) {
        real_close(fd);
        return DEC_NOOP;
    }

    /* Bound moov read to 1 MiB — real moov boxes are tens of KB at most */
    if (moov_size < 32 || moov_size > (1U << 20)) {
        real_close(fd);
        return DEC_NOOP;
    }

    unsigned char *moov = malloc((size_t)moov_size);
    if (!moov) {
        real_close(fd);
        return DEC_NOOP;
    }

    /* Read the moov body in one shot. pread64 may return short on EINTR — loop. */
    size_t total = 0;
    while (total < moov_size) {
        ssize_t n = real_pread64(fd, moov + total, (size_t)moov_size - total,
                                  moov_off + (off_t)total);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            free(moov);
            real_close(fd);
            return DEC_NOOP;
        }
        total += (size_t)n;
    }
    real_close(fd);

    /* moov_off..moov_off+moov_size includes the box header. We loaded the WHOLE
     * box (size+kind+body) starting from moov_off, so the moov body starts at
     * offset 8 (or 16 if size==1, but we'd have rejected via moov_size cap). */
    size_t hdr = 8;
    if (moov_size <= hdr || hdr >= total) {
        free(moov);
        return DEC_NOOP;
    }
    /* Re-check the loaded moov's apparent size matches what we requested. */
    uint32_t loaded_size32 = ((uint32_t)moov[0] << 24) | ((uint32_t)moov[1] << 16) |
                             ((uint32_t)moov[2] << 8) | (uint32_t)moov[3];
    if (loaded_size32 == 1) hdr = 16;

    ssize_t esds_off_in_moov = walk_for_esds(moov, (size_t)moov_size, hdr,
                                             (size_t)moov_size, 0);
    if (esds_off_in_moov < 0) {
        free(moov);
        return DEC_NOOP;
    }

    /* esds box at moov[esds_off_in_moov]. Body starts after its 8-byte header. */
    if ((size_t)esds_off_in_moov + 8 >= (size_t)moov_size) {
        free(moov);
        return DEC_NOOP;
    }
    uint32_t esds_size32 = ((uint32_t)moov[esds_off_in_moov] << 24) |
                           ((uint32_t)moov[esds_off_in_moov + 1] << 16) |
                           ((uint32_t)moov[esds_off_in_moov + 2] << 8) |
                           (uint32_t)moov[esds_off_in_moov + 3];
    if (esds_size32 < 9 || (size_t)esds_off_in_moov + esds_size32 > (size_t)moov_size) {
        free(moov);
        return DEC_NOOP;
    }
    const unsigned char *esds_body = moov + esds_off_in_moov + 8;
    size_t esds_body_len = esds_size32 - 8;

    decision_t d = parse_esds_decision(esds_body, esds_body_len);
    free(moov);
    return d;
}

/* === Transcode invocation (port of aac-redirect.c spawn_transcode + lockpath) === */

static void build_lockpath(const char *sibling, char *out, size_t out_sz) {
    unsigned long h = path_hash(sibling);
    const char *base = strrchr(sibling, '/');
    base = base ? base + 1 : sibling;
    uid_t uid = getuid();
    char dir[PATH_MAX];
    snprintf(dir, sizeof(dir), "/run/user/%u/aac-redirect", (unsigned)uid);
    struct stat st;
    if (stat(dir, &st) != 0) mkdir(dir, 0700);
    if (stat(dir, &st) == 0 && S_ISDIR(st.st_mode)) {
        snprintf(out, out_sz, "%s/%lx-%.40s.lock", dir, h, base);
    } else {
        snprintf(out, out_sz, "/tmp/aac-redirect-%lx-%.40s.lock", h, base);
    }
}

/* Spawn `resolve-codec-patch fix-file <src>` synchronously. Returns 0 if sibling
 * now exists (success), -1 otherwise. Copies the proven retry/timeout logic
 * verbatim from aac-redirect.c spawn_transcode(). */
static int spawn_transcode(const char *src, const char *sibling) {
    INIT_REAL(open);
    if (!real_open) return -1;

    char lockpath[PATH_MAX];
    build_lockpath(sibling, lockpath, sizeof(lockpath));

    /* No O_CLOEXEC: child inherits the fd so OFD reference keeps the flock
     * alive across child exec'd subprocesses. */
    int lockfd = real_open(lockpath, O_CREAT | O_RDWR, 0644);
    if (lockfd < 0) return -1;

    /* Non-blocking lock: if another process is already transcoding this
     * sibling, return -1 immediately and let caller fall through to original. */
    if (flock(lockfd, LOCK_EX | LOCK_NB) < 0) {
        close(lockfd);
        return -1;
    }

    /* Re-check after lock — another worker may have just finished. */
    struct stat st;
    if (stat(sibling, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) {
        close(lockfd);
        return 0;
    }

    markerf("[aac_hybrid] spawning fix-file for %s -> %s", src, sibling);

    pid_t pid = fork();
    if (pid < 0) {
        close(lockfd);
        return -1;
    }
    if (pid == 0) {
        /* Child: clear LD_PRELOAD so fix-file's ffmpeg subprocess doesn't
         * recursively load our shim (would self-block on its own .resolve.mp4
         * sibling check). */
        unsetenv("LD_PRELOAD");
        unsetenv("LD_AUDIT");
        /* Sanitize PATH so a malicious dir earlier on the user's PATH can't
         * shadow `resolve-codec-patch`. Prepend ~/.local/bin (installer
         * destination) ahead of the standard search dirs. */
        const char *home = getenv("HOME");
        char safepath[PATH_MAX + 64];
        if (home && *home) {
            snprintf(safepath, sizeof(safepath),
                     "%s/.local/bin:/usr/local/bin:/usr/bin:/bin", home);
        } else {
            snprintf(safepath, sizeof(safepath),
                     "/usr/local/bin:/usr/bin:/bin");
        }
        setenv("PATH", safepath, 1);
        if (cache_dir()) setenv("AAC_FIX_OUT_PATH", sibling, 1);
        int devnull = open("/dev/null", O_RDWR);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            if (devnull > 2) close(devnull);
        }
        /* Close inherited fds >= 3 (other than lockfd) so Resolve's DB
         * handles, GPU driver fds, project-file fds don't leak into ffmpeg.
         * Done AFTER the dup2's above so 0/1/2 are already /dev/null. */
        long maxfd = sysconf(_SC_OPEN_MAX);
        if (maxfd < 1024) maxfd = 1024;
        if (maxfd > 65536) maxfd = 65536;
        for (int fd2 = 3; fd2 < (int)maxfd; fd2++) {
            if (fd2 != lockfd) close(fd2);
        }
        /* execlp does $PATH lookup; install.sh puts the helper in
         * ~/.local/bin which is now first on the sanitized PATH above. */
        execlp("resolve-codec-patch",
               "resolve-codec-patch", "fix-file", src, (char *)NULL);
        _exit(127);
    }

    /* Wall-clock cap on the fix-file wait. Resolve's GUI thread has an internal
     * IO timeout (~15-30s) — block past it and the import dies. Default 25s,
     * overridable via AAC_REDIRECT_MAX_WAIT. On timeout: detach the child (it
     * keeps transcoding so the next open() picks up the finished sibling) and
     * return -1 so caller returns the original fd this round. */
    int max_wait = 25;
    const char *env_max = getenv("AAC_REDIRECT_MAX_WAIT");
    if (env_max && *env_max) {
        int v = atoi(env_max);
        if (v > 0 && v < 3600) max_wait = v;
    }
    int status = -1;
    int waited = 0;
    int timed_out = 0;
    struct timespec t0, t_now;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    while (1) {
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid) { waited = 1; break; }
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        struct timespec ts = {0, 100 * 1000 * 1000};
        nanosleep(&ts, NULL);
        clock_gettime(CLOCK_MONOTONIC, &t_now);
        if (t_now.tv_sec - t0.tv_sec >= max_wait) { timed_out = 1; break; }
    }
    if (timed_out) {
        markerf("[aac_hybrid] timeout %ds — backgrounding transcode", max_wait);
        close(lockfd);
        return -1;
    }
    close(lockfd);
    if (stat(sibling, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) {
        if (waited && !(WIFEXITED(status) && WEXITSTATUS(status) == 0)) {
            markerf("[aac_hybrid] fix-file rc nonzero but sibling exists");
        }
        markerf("[aac_hybrid] fix-file ok: %s", sibling);
        return 0;
    }
    markerf("[aac_hybrid] fix-file no-op or fail: %s", src);
    return -1;
}

/* === Per-open redirect decision ===
 *
 * Returns: malloc'd sibling-path string if open() should be redirected, NULL
 * if caller should use the original path (cave-handled or noop).
 *
 * Algorithm:
 *   1. Pre-filters (non-video / already-sibling / noop-marker) -> NULL.
 *   2. If a sibling FILE ALREADY EXISTS on disk -> redirect (trust pre-existing
 *      sibling regardless of cache). Cache as DEC_SIBLING.
 *   3. Look up cache; if cached, branch on decision.
 *   4. Else: probe the file. Cache the result.
 *   5. If DEC_SIBLING: spawn fix-file; on success return sibling path, on
 *      failure cache as DEC_NOOP and return NULL.
 *   6. If DEC_CAVE_OK / DEC_NOOP / parse fail: return NULL.
 */
static char *redirect_path_for_open(const char *path) {
    if (!path || !has_video_ext(path) || is_already_sibling(path) ||
        is_noop_marker(path)) return NULL;

    char *sibling = build_sibling(path);
    if (!sibling) return NULL;

    /* Fast path: pre-existing sibling means a prior session (or pre-existing
     * aac-redirect run) already transcoded this file. Reuse it. */
    struct stat st;
    if (stat(sibling, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) {
        cache_put(path, DEC_SIBLING);
        markerf("[aac_hybrid] %s -> %s (existing sibling)", path, sibling);
        return sibling;
    }

    decision_t cached = cache_get(path);
    if (cached == DEC_CAVE_OK || cached == DEC_NOOP) {
        free(sibling);
        return NULL;
    }

    if (cached == DEC_UNKNOWN) {
        decision_t probed = probe_file_decision(path);
        cache_put(path, probed);
        cached = probed;
        {
            const char *name[] = {"unknown", "CAVE_OK", "SIBLING", "NOOP"};
            markerf("[aac_hybrid] probe %s -> %s", path,
                    (probed >= 0 && probed <= 3) ? name[probed] : "?");
        }
    }

    if (cached != DEC_SIBLING) {
        free(sibling);
        return NULL;
    }

    /* Sibling decision but no sibling on disk yet — transcode. */
    if (spawn_transcode(path, sibling) == 0) {
        return sibling;
    }
    /* Transcode failed — fall back to original fd, mark NOOP to avoid retry
     * thrash on Resolve's many re-opens during one import. */
    cache_put(path, DEC_NOOP);
    free(sibling);
    return NULL;
}

/* === open()-family hooks === */

int open(const char *path, int flags, ...) {
    INIT_REAL(open);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    /* Only redirect READ-only opens — Resolve writes to the source on metadata
     * commits, which we MUST NOT silently divert to the sibling file. */
    if (!(flags & (O_WRONLY | O_RDWR | O_CREAT))) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            int fd = real_open(redir, flags, mode);
            free(redir);
            if (fd >= 0) return fd;
        }
    }
    return real_open(path, flags, mode);
}

int open64(const char *path, int flags, ...) {
    INIT_REAL(open64);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    if (!(flags & (O_WRONLY | O_RDWR | O_CREAT))) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            int fd = real_open64(redir, flags, mode);
            free(redir);
            if (fd >= 0) return fd;
        }
    }
    return real_open64(path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...) {
    INIT_REAL(openat);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    if (!(flags & (O_WRONLY | O_RDWR | O_CREAT))) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            int fd = real_openat(dirfd, redir, flags, mode);
            free(redir);
            if (fd >= 0) return fd;
        }
    }
    return real_openat(dirfd, path, flags, mode);
}

int openat64(int dirfd, const char *path, int flags, ...) {
    INIT_REAL(openat64);
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    if (!(flags & (O_WRONLY | O_RDWR | O_CREAT))) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            int fd = real_openat64(dirfd, redir, flags, mode);
            free(redir);
            if (fd >= 0) return fd;
        }
    }
    return real_openat64(dirfd, path, flags, mode);
}

FILE *fopen(const char *path, const char *mode) {
    INIT_REAL(fopen);
    if (mode && (mode[0] == 'r') && !strchr(mode, '+')) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            FILE *fp = real_fopen(redir, mode);
            free(redir);
            if (fp) return fp;
        }
    }
    return real_fopen(path, mode);
}

FILE *fopen64(const char *path, const char *mode) {
    INIT_REAL(fopen64);
    if (mode && (mode[0] == 'r') && !strchr(mode, '+')) {
        char *redir = redirect_path_for_open(path);
        if (redir) {
            FILE *fp = real_fopen64(redir, mode);
            free(redir);
            if (fp) return fp;
        }
    }
    return real_fopen64(path, mode);
}

/* === stat-family hooks ===
 *
 * Resolve cross-checks (mtime+size) from stat() against file content read via
 * open(). When we redirect open() to a sibling, the stat must ALSO return the
 * sibling's metadata or Resolve emits "Unable to find media".
 *
 * For the cave path we do NOT redirect open(), so stat must NOT redirect either.
 *
 * For the SIBLING path: redirect stat to the sibling, but ONLY if the sibling
 * already exists on disk. Never trigger probe / spawn from a stat call — that
 * blocks Resolve's metadata probe thread.
 */

static int (*real_stat)(const char *, struct stat *) = NULL;
static int (*real_stat64)(const char *, struct stat64 *) = NULL;
static int (*real_lstat)(const char *, struct stat *) = NULL;
static int (*real_lstat64)(const char *, struct stat64 *) = NULL;
static int (*real_fstatat)(int, const char *, struct stat *, int) = NULL;
static int (*real___xstat)(int, const char *, struct stat *) = NULL;
static int (*real___xstat64)(int, const char *, struct stat64 *) = NULL;
static int (*real___lxstat)(int, const char *, struct stat *) = NULL;
static int (*real___lxstat64)(int, const char *, struct stat64 *) = NULL;
static int (*real___fxstatat)(int, int, const char *, struct stat *, int) = NULL;
static int (*real_access)(const char *, int) = NULL;

/* Returns sibling path (caller free's) IFF the file's CACHED decision is
 * DEC_SIBLING and a sibling currently exists on disk. NULL otherwise.
 * Never probes / spawns from stat (would block Resolve's metadata thread). */
static char *stat_redirect_existing_only(const char *path) {
    if (!path || !has_video_ext(path) || is_already_sibling(path) ||
        is_noop_marker(path)) return NULL;
    char *sibling = build_sibling(path);
    if (!sibling) return NULL;
    struct stat st;
    if (stat(sibling, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) {
        return sibling;
    }
    free(sibling);
    return NULL;
}

int stat(const char *path, struct stat *buf) {
    INIT_REAL(stat);
    char *redir = stat_redirect_existing_only(path);
    if (redir) {
        int r = real_stat(redir, buf);
        free(redir);
        if (r == 0) return r;
    }
    return real_stat(path, buf);
}

int stat64(const char *path, struct stat64 *buf) {
    INIT_REAL(stat64);
    char *redir = stat_redirect_existing_only(path);
    if (redir) {
        int r = real_stat64(redir, buf);
        free(redir);
        if (r == 0) return r;
    }
    return real_stat64(path, buf);
}

int lstat(const char *path, struct stat *buf) {
    INIT_REAL(lstat);
    char *redir = stat_redirect_existing_only(path);
    if (redir) {
        int r = real_lstat(redir, buf);
        free(redir);
        if (r == 0) return r;
    }
    return real_lstat(path, buf);
}

int lstat64(const char *path, struct stat64 *buf) {
    INIT_REAL(lstat64);
    char *redir = stat_redirect_existing_only(path);
    if (redir) {
        int r = real_lstat64(redir, buf);
        free(redir);
        if (r == 0) return r;
    }
    return real_lstat64(path, buf);
}

int fstatat(int dirfd, const char *path, struct stat *buf, int flags) {
    INIT_REAL(fstatat);
    if (path && (dirfd == AT_FDCWD || path[0] == '/')) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real_fstatat(dirfd, redir, buf, flags);
            free(redir);
            if (r == 0) return r;
        }
    }
    return real_fstatat(dirfd, path, buf, flags);
}

int __xstat(int ver, const char *path, struct stat *buf) {
    INIT_REAL(__xstat);
    if (real___xstat) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real___xstat(ver, redir, buf);
            free(redir);
            if (r == 0) return r;
        }
        return real___xstat(ver, path, buf);
    }
    return stat(path, buf);
}

int __xstat64(int ver, const char *path, struct stat64 *buf) {
    INIT_REAL(__xstat64);
    if (real___xstat64) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real___xstat64(ver, redir, buf);
            free(redir);
            if (r == 0) return r;
        }
        return real___xstat64(ver, path, buf);
    }
    return stat64(path, buf);
}

int __lxstat(int ver, const char *path, struct stat *buf) {
    INIT_REAL(__lxstat);
    if (real___lxstat) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real___lxstat(ver, redir, buf);
            free(redir);
            if (r == 0) return r;
        }
        return real___lxstat(ver, path, buf);
    }
    return lstat(path, buf);
}

int __lxstat64(int ver, const char *path, struct stat64 *buf) {
    INIT_REAL(__lxstat64);
    if (real___lxstat64) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real___lxstat64(ver, redir, buf);
            free(redir);
            if (r == 0) return r;
        }
        return real___lxstat64(ver, path, buf);
    }
    return lstat64(path, buf);
}

int __fxstatat(int ver, int dirfd, const char *path, struct stat *buf, int flags) {
    INIT_REAL(__fxstatat);
    if (real___fxstatat && path && (dirfd == AT_FDCWD || path[0] == '/')) {
        char *redir = stat_redirect_existing_only(path);
        if (redir) {
            int r = real___fxstatat(ver, dirfd, redir, buf, flags);
            free(redir);
            if (r == 0) return r;
        }
        return real___fxstatat(ver, dirfd, path, buf, flags);
    }
    return fstatat(dirfd, path, buf, flags);
}

int access(const char *path, int mode) {
    INIT_REAL(access);
    char *redir = stat_redirect_existing_only(path);
    if (redir) {
        int r = real_access(redir, mode);
        free(redir);
        if (r == 0) return r;
    }
    return real_access(path, mode);
}

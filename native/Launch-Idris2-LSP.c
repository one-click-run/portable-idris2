#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <windows.h>

#define PATH_BUFFER 32768
#define IO_BUFFER 16384
#define HEADER_BUFFER 65536

typedef struct {
    HANDLE source;
    HANDLE destination;
} StreamCopyContext;

static int join_path(wchar_t *out, size_t count, const wchar_t *root, const wchar_t *suffix) {
    return _snwprintf_s(out, count, _TRUNCATE, L"%ls\\%ls", root, suffix) >= 0;
}

static int write_all(HANDLE destination, const void *data, DWORD length) {
    const unsigned char *cursor = data;
    while (length > 0) {
        DWORD written = 0;
        if (!WriteFile(destination, cursor, length, &written, NULL) || written == 0) return 0;
        cursor += written;
        length -= written;
    }
    return 1;
}

static DWORD WINAPI copy_stream(LPVOID parameter) {
    StreamCopyContext *context = parameter;
    unsigned char buffer[IO_BUFFER];
    DWORD received = 0;
    while (ReadFile(context->source, buffer, sizeof(buffer), &received, NULL) && received > 0) {
        if (!write_all(context->destination, buffer, received)) break;
    }
    CloseHandle(context->destination);
    return 0;
}

static int find_idris_prefix(const wchar_t *root, wchar_t *prefix, size_t prefix_count) {
    wchar_t pattern[PATH_BUFFER];
    if (!join_path(pattern, PATH_BUFFER, root, L"data\\pack-state\\install\\*")) return 0;
    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(pattern, &entry);
    if (search == INVALID_HANDLE_VALUE) return 0;
    int found = 0;
    do {
        if (!(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0) continue;
        wchar_t candidate[PATH_BUFFER];
        if (_snwprintf_s(candidate, PATH_BUFFER, _TRUNCATE,
                L"%ls\\data\\pack-state\\install\\%ls\\idris2", root, entry.cFileName) < 0) continue;
        wchar_t compiler[PATH_BUFFER];
        if (!join_path(compiler, PATH_BUFFER, candidate, L"bin\\idris2.cmd")) continue;
        if (GetFileAttributesW(compiler) != INVALID_FILE_ATTRIBUTES) {
            wcsncpy_s(prefix, prefix_count, candidate, _TRUNCATE);
            found = 1;
            break;
        }
    } while (FindNextFileW(search, &entry));
    FindClose(search);
    return found;
}

static int set_root_variable(const wchar_t *name, const wchar_t *root, const wchar_t *suffix) {
    wchar_t value[PATH_BUFFER];
    return join_path(value, PATH_BUFFER, root, suffix) && SetEnvironmentVariableW(name, value);
}

static int configure_environment(const wchar_t *root, const wchar_t *idris_prefix) {
    if (!SetEnvironmentVariableW(L"IDRIS2_PREFIX", idris_prefix)) return 0;
    SetEnvironmentVariableW(L"CHEZ", L"scheme");
    SetEnvironmentVariableW(L"SCHEME", L"scheme");
    SetEnvironmentVariableW(L"ONE_CLICK_RUN_OFFLINE_RUNTIME", L"1");
    SetEnvironmentVariableW(L"MSYSTEM", L"MINGW64");
    SetEnvironmentVariableW(L"MSYS2_PATH_TYPE", L"inherit");
    SetEnvironmentVariableW(L"IDRIS2_CC", L"gcc");
    if (!set_root_variable(L"HOME", root, L"data\\home") ||
        !set_root_variable(L"PACK_USER_DIR", root, L"data\\pack-config") ||
        !set_root_variable(L"PACK_STATE_DIR", root, L"data\\pack-state") ||
        !set_root_variable(L"PACK_CACHE_DIR", root, L"data\\pack-cache") ||
        !set_root_variable(L"PACK_BIN_DIR", root, L"bin") ||
        !set_root_variable(L"GIT_CONFIG_GLOBAL", root, L"data\\gitconfig") ||
        !set_root_variable(L"XDG_CACHE_HOME", root, L"data\\xdg-cache") ||
        !set_root_variable(L"XDG_CONFIG_HOME", root, L"data\\xdg-config") ||
        !set_root_variable(L"XDG_DATA_HOME", root, L"data\\xdg-data") ||
        !set_root_variable(L"XDG_STATE_HOME", root, L"data\\xdg-state")) return 0;

    wchar_t old_path[PATH_BUFFER];
    DWORD old_length = GetEnvironmentVariableW(L"PATH", old_path, PATH_BUFFER);
    if (old_length >= PATH_BUFFER) return 0;
    if (old_length == 0) old_path[0] = L'\0';
    wchar_t path[PATH_BUFFER];
    if (_snwprintf_s(path, PATH_BUFFER, _TRUNCATE,
            L"%ls\\bin\\idris2-lsp_app;%ls\\bin;%ls\\bin;%ls\\chez\\bin\\ta6nt;%ls\\runtime;%ls\\msys2\\mingw64\\bin;%ls\\msys2\\usr\\bin;%ls",
            root, root, idris_prefix, root, root, root, root, old_path) < 0) return 0;
    return SetEnvironmentVariableW(L"PATH", path);
}

static int proxy_lsp_output(HANDLE source, HANDLE destination) {
    for (;;) {
        char header[HEADER_BUFFER];
        size_t header_length = 0;
        int consecutive_newlines = 0;
        while (consecutive_newlines < 2) {
            unsigned char byte = 0;
            DWORD received = 0;
            if (!ReadFile(source, &byte, 1, &received, NULL) || received == 0) {
                return header_length == 0;
            }
            if (header_length + 1 >= HEADER_BUFFER) return 0;
            header[header_length++] = (char)byte;
            if (byte == '\n') consecutive_newlines++;
            else if (byte != '\r') consecutive_newlines = 0;
        }
        header[header_length] = '\0';

        unsigned long content_length = 0;
        char *line = header;
        while (line < header + header_length) {
            if (_strnicmp(line, "Content-Length:", 15) == 0) {
                content_length = strtoul(line + 15, NULL, 10);
                break;
            }
            char *next = strchr(line, '\n');
            if (next == NULL) break;
            line = next + 1;
        }
        if (content_length == 0) return 0;

        char canonical_header[64];
        int canonical_length = sprintf_s(canonical_header, sizeof(canonical_header),
            "Content-Length: %lu\r\n\r\n", content_length);
        if (canonical_length <= 0 || !write_all(destination, canonical_header, (DWORD)canonical_length)) return 0;

        unsigned char buffer[IO_BUFFER];
        unsigned long remaining = content_length;
        while (remaining > 0) {
            DWORD requested = remaining > IO_BUFFER ? IO_BUFFER : (DWORD)remaining;
            DWORD received = 0;
            if (!ReadFile(source, buffer, requested, &received, NULL) || received == 0) return 0;
            if (!write_all(destination, buffer, received)) return 0;
            remaining -= received;
        }
    }
}

int wmain(void) {
    wchar_t root[PATH_BUFFER];
    DWORD root_length = GetModuleFileNameW(NULL, root, PATH_BUFFER);
    if (root_length == 0 || root_length >= PATH_BUFFER) return 2;
    wchar_t *separator = wcsrchr(root, L'\\');
    if (separator == NULL) return 2;
    *separator = L'\0';

    wchar_t idris_prefix[PATH_BUFFER];
    if (!find_idris_prefix(root, idris_prefix, PATH_BUFFER) || !configure_environment(root, idris_prefix)) {
        fwprintf(stderr, L"Unable to configure the portable Idris 2 environment.\n");
        return 2;
    }

    wchar_t scheme[PATH_BUFFER];
    wchar_t program[PATH_BUFFER];
    if (!join_path(scheme, PATH_BUFFER, root, L"chez\\bin\\ta6nt\\scheme.exe") ||
        !join_path(program, PATH_BUFFER, root, L"bin\\idris2-lsp_app\\idris2-lsp.so")) return 2;
    if (GetFileAttributesW(scheme) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(program) == INVALID_FILE_ATTRIBUTES) {
        fwprintf(stderr, L"Bundled Idris 2 LSP files are missing.\n");
        return 2;
    }

    SECURITY_ATTRIBUTES security = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };
    HANDLE child_stdin_read, child_stdin_write, child_stdout_read, child_stdout_write;
    if (!CreatePipe(&child_stdin_read, &child_stdin_write, &security, 0) ||
        !CreatePipe(&child_stdout_read, &child_stdout_write, &security, 0)) return 2;
    SetHandleInformation(child_stdin_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(child_stdout_read, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW startup;
    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = child_stdin_read;
    startup.hStdOutput = child_stdout_write;
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process;
    ZeroMemory(&process, sizeof(process));

    wchar_t command_line[PATH_BUFFER];
    if (_snwprintf_s(command_line, PATH_BUFFER, _TRUNCATE,
            L"\"%ls\" --program \"%ls\"", scheme, program) < 0) return 2;
    if (!CreateProcessW(scheme, command_line, NULL, NULL, TRUE, CREATE_NO_WINDOW,
            NULL, NULL, &startup, &process)) {
        fwprintf(stderr, L"Unable to start the bundled Idris 2 LSP server (error %lu).\n", GetLastError());
        return 2;
    }
    CloseHandle(child_stdin_read);
    CloseHandle(child_stdout_write);

    StreamCopyContext input = { GetStdHandle(STD_INPUT_HANDLE), child_stdin_write };
    HANDLE input_thread = CreateThread(NULL, 0, copy_stream, &input, 0, NULL);
    int proxy_ok = proxy_lsp_output(child_stdout_read, GetStdHandle(STD_OUTPUT_HANDLE));
    CloseHandle(child_stdout_read);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code = 2;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (input_thread != NULL) CloseHandle(input_thread);
    return proxy_ok ? (int)exit_code : 2;
}

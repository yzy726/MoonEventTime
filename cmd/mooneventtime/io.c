/* SPDX-License-Identifier: Apache-2.0
 * Private synchronous CLI adapter. Bytes are borrowed for each call only.
 * No MoonBit allocation or ownership transfer crosses these functions.
 */
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#else
#include <unistd.h>
#endif

static FILE *input_stream = NULL;

#ifdef _WIN32
static wchar_t *wide_path(const char *path) {
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  if (count <= 0) return NULL;
  wchar_t *result = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
  if (!result) return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, result, count)) {
    free(result);
    return NULL;
  }
  return result;
}
#endif

static FILE *open_path(const char *path, int writing) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return NULL;
  FILE *stream = _wfopen(wide, writing ? L"wbx" : L"rb");
  free(wide);
  return stream;
#else
  return fopen(path, writing ? "wbx" : "rb");
#endif
}

static void remove_path(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (wide) { _wremove(wide); free(wide); }
#else
  remove(path);
#endif
}

MOONBIT_FFI_EXPORT int32_t mooneventtime_open(moonbit_bytes_t path) {
  if (input_stream) return -1;
  input_stream = open_path((const char *)path, 0);
  return input_stream ? 0 : -1;
}

MOONBIT_FFI_EXPORT int32_t mooneventtime_read(moonbit_bytes_t buffer) {
  if (!input_stream) return -1;
  size_t count = fread(buffer, 1, (size_t)Moonbit_array_length(buffer), input_stream);
  if (ferror(input_stream)) return -1;
  return (int32_t)count;
}

MOONBIT_FFI_EXPORT int32_t mooneventtime_close(void) {
  if (!input_stream) return 0;
  FILE *stream = input_stream;
  input_stream = NULL;
  return fclose(stream);
}

MOONBIT_FFI_EXPORT void mooneventtime_stderr(moonbit_bytes_t message) {
  fwrite(message, 1, (size_t)Moonbit_array_length(message), stderr);
  fputc('\n', stderr);
  fflush(stderr);
}

/* Exclusive same-directory temporary creation, then atomic name replacement.
 * This is not a durable transaction with source offsets or downstream output.
 */
MOONBIT_FFI_EXPORT int32_t mooneventtime_write_snapshot(moonbit_bytes_t path,
                                                     moonbit_bytes_t data) {
  const char *destination = (const char *)path;
  size_t length = strlen(destination);
  char *temporary = (char *)malloc(length + 64);
  if (!temporary) return -1;
#ifdef _WIN32
  unsigned long pid = (unsigned long)GetCurrentProcessId();
#else
  unsigned long pid = (unsigned long)getpid();
#endif
  snprintf(temporary, length + 64, "%s.%lu.tmp", destination, pid);
  FILE *stream = open_path(temporary, 1);
  if (!stream) { free(temporary); return -1; }
  size_t wanted = (size_t)Moonbit_array_length(data);
  int failed = fwrite(data, 1, wanted, stream) != wanted;
  if (fflush(stream) != 0) failed = 1;
  if (fclose(stream) != 0) failed = 1;
  if (!failed) {
#ifdef _WIN32
    wchar_t *from = wide_path(temporary);
    wchar_t *to = wide_path(destination);
    failed = !from || !to || !MoveFileExW(from, to, MOVEFILE_REPLACE_EXISTING);
    free(from);
    free(to);
#else
    failed = rename(temporary, destination) != 0;
#endif
  }
  if (failed) remove_path(temporary);
  free(temporary);
  return failed ? -1 : 0;
}

MOONBIT_FFI_EXPORT void mooneventtime_exit(int32_t status) { exit(status); }

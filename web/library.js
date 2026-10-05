addToLibrary({
  toad_storage_read__deps: ['$UTF8ToString'],
  toad_storage_read: function(key, data, capacity) {
    try {
      const text = localStorage.getItem(UTF8ToString(key));
      if (text === null) return -1;
      if (text.length > Math.ceil(capacity / 3) * 4) return -2;
      const bytes = atob(text);
      if (bytes.length > capacity) return -2;
      for (let i = 0; i < bytes.length; i++) HEAPU8[data + i] = bytes.charCodeAt(i);
      return bytes.length;
    } catch (_) { return -3; }
  },
  toad_storage_write__deps: ['$UTF8ToString'],
  toad_storage_write: function(key, data, size) {
    try {
      let text = '';
      for (let i = 0; i < size; i += 8192) {
        text += String.fromCharCode.apply(null, HEAPU8.subarray(data + i, data + Math.min(size, i + 8192)));
      }
      localStorage.setItem(UTF8ToString(key), btoa(text));
      return 0;
    } catch (_) { return -1; }
  }
});

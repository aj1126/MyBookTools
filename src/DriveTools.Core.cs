using System;
using System.IO;
using System.Security.Cryptography;
using System.Collections.Concurrent;
using System.Threading;

namespace DriveTools.Core {
    public class AuditEngine {
        public BlockingCollection<string> FileQueue;
        public ConcurrentDictionary<string, string> HashCache;
        public ReaderWriterLockSlim FileLock;
        public string LogPath;
        
        private int _processedCount;
        private int _errorCount;
        private string _activeFile;

        public AuditEngine(int queueBounds, string logPath) {
            FileQueue = new BlockingCollection<string>(queueBounds);
            HashCache = new ConcurrentDictionary<string, string>();
            FileLock = new ReaderWriterLockSlim();
            LogPath = logPath;
            _processedCount = 0;
            _errorCount = 0;
            _activeFile = string.Empty;
        }

        public int ProcessedCount => _processedCount;
        public int ErrorCount => _errorCount;
        public string ActiveFile => _activeFile;

        public void StartConsumerWorker() {
            using (SHA256 hasher = SHA256.Create()) {
                foreach (string filePath in FileQueue.GetConsumingEnumerable()) {
                    _activeFile = filePath;
                    try {
                        using (FileStream fs = File.Open(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                            byte[] hashBytes = hasher.ComputeHash(fs);
                            string hashString = BitConverter.ToString(hashBytes).Replace("-", "");
                            
                            HashCache.TryAdd(filePath, hashString);
                            string csvRow = $"\"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\",\"{filePath.Replace("\"", "\"\"")}\",\"{hashString}\"\r\n";
                            
                            FileLock.EnterWriteLock();
                            try { File.AppendAllText(LogPath, csvRow); }
                            finally { FileLock.ExitWriteLock(); }
                            
                            Interlocked.Increment(ref _processedCount);
                        }
                    }
                    catch {
                        Interlocked.Increment(ref _errorCount);
                    }
                }
            }
        }
    }
}
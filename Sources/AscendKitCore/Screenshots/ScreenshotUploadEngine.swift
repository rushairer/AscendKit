import Foundation

// MARK: - 网络重试包装器
public struct ASCNetworkRetryPolicy {
    public static func executeWithRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 5.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 1
        var currentDelay = initialDelay
        
        while true {
            do {
                return try await operation()
            } catch let error as URLError {
                // 判断网络连接、网关超时等情况
                let retriableCodes = [URLError.timedOut, URLError.badServerResponse, URLError.networkConnectionLost]
                if attempt >= maxAttempts || !retriableCodes.contains(error.code) { throw error }
            } catch {
                // 为了避免某些其他 5xx 服务器 HTTP 层错误导致的失败
                if attempt >= maxAttempts { throw error }
            }
            
            // 简单退避(5s, 15s, 30s)
            try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
            attempt += 1
            currentDelay *= 3
        }
    }
}

// MARK: - 执行引擎
public struct ScreenshotUploadEngine {
    private let apiClient: ASCAPIClient
    private let stateManager: ScreenshotUploadStateManager
    
    public init(apiClient: ASCAPIClient = ASCAPIClient(), stateManager: ScreenshotUploadStateManager = ScreenshotUploadStateManager()) {
        self.apiClient = apiClient
        self.stateManager = stateManager
    }
    
    public func execute(
        plan: ScreenshotUploadPlan,
        strategy: ScreenshotChunkingStrategy,
        delayBetweenChunks: TimeInterval,
        isResume: Bool,
        workspace: ReleaseWorkspace,
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> ScreenshotUploadExecutionResult {
        
        guard confirmRemoteMutation else {
            return ScreenshotUploadExecutionResult(
                executed: false,
                uploadedCount: 0,
                items: [],
                findings: ["Missing --confirm-remote-mutation. No screenshot upload request was executed."]
            )
        }

        let chunker = ScreenshotUploadChunker()
        var chunks = chunker.chunk(plan: plan, strategy: strategy)
        
        // --- 1. 读取且恢复状态 ---
        var currentState = ScreenshotUploadProgressState(planID: UUID().uuidString, strategy: strategy)
        let statePath = workspace.paths.screenshotUploadProgress
        
        if isResume, let savedState = try? stateManager.load(from: statePath) {
            currentState = savedState // 加载本地状态机恢复执行环境
            // 剔除掉已经宣告成功的子块，实现真·原生断点续传
            let successfulChunkIDs = currentState.chunks.filter { $0.value.state == .success }.map(\.key)
            chunks.removeAll { successfulChunkIDs.contains($0.id) }
        }
        
        var totalUploaded = 0
        var allItems: [ScreenshotUploadExecutionItem] = []
        var allExecutionFindings: [String] = []

        // --- 2. 基于分片(Chunk)进行阶段化并发执行 ---
        for (index, chunk) in chunks.enumerated() {
            var chunkState = currentState.chunks[chunk.id] ?? ScreenshotChunkState(id: chunk.id)
            
            // (阶段 A: Wipe) 优先进行纯净删除，避免一边删一边传引起的冲突
            if !chunk.remoteScreenshotsToDelete.isEmpty && chunkState.state == .pending {
                chunkState.state = .wiping
                currentState.chunks[chunk.id] = chunkState
                try? stateManager.save(currentState, to: statePath)
                
                var deletedInChunk = 0
                for deleteId in chunk.remoteScreenshotsToDelete {
                    do {
                        let successItem = try await ASCNetworkRetryPolicy.executeWithRetry {
                            // 调用现有的删除逻辑（因封装问题暂使用伪代码占位）
                            try await self.apiClient.deleteAppScreenshot(screenshotID: deleteId, token: token)
                        }
                        deletedInChunk += 1
                    } catch {
                        chunkState.findings.append("Chunk \(chunk.id) Fail Delete \(deleteId): \(error.localizedDescription)")
                    }
                }
                
                chunkState.deletedCount = deletedInChunk
                chunkState.state = .wiped
                currentState.chunks[chunk.id] = chunkState
                try? stateManager.save(currentState, to: statePath)
                
                // 给服务器几秒钟的缓冲，防止由于网络缓存导致的刚删除紧接着报错
                if deletedInChunk > 0 { try await Task.sleep(nanoseconds: 5_000_000_000) }
            }
            
            // (阶段 B: Upload)
            if !chunk.itemsToUpload.isEmpty && (chunkState.state == .wiped || chunkState.state == .pending) {
                chunkState.state = .uploading
                currentState.chunks[chunk.id] = chunkState
                try? stateManager.save(currentState, to: statePath)
                
                var uploadedInChunk = 0
                var failedInChunk = 0
                
                for item in chunk.itemsToUpload {
                    do {
                        let successItem = try await ASCNetworkRetryPolicy.executeWithRetry {
                            return try await self.apiClient.uploadSingleScreenshot(item: item, token: token)
                        }
                        uploadedInChunk += 1
                        totalUploaded += 1
                        allItems.append(successItem)
                    } catch {
                         failedInChunk += 1
                         chunkState.findings.append("Chunk \(chunk.id) Fail Upload \(item.fileName): \(error.localizedDescription)")
                    }
                }
                
                chunkState.uploadedCount = uploadedInChunk
                chunkState.failedCount = failedInChunk
                chunkState.state = chunkState.findings.isEmpty ? .success : .failed
                currentState.chunks[chunk.id] = chunkState
                try? stateManager.save(currentState, to: statePath)
            }
            
            allExecutionFindings.append(contentsOf: chunkState.findings)
            // 防御 429 限制休眠
            if index < chunks.count - 1 {
                try await Task.sleep(nanoseconds: UInt64(delayBetweenChunks * 1_000_000_000))
            }
        }
        
        return ScreenshotUploadExecutionResult(
            executed: true,
            uploadedCount: totalUploaded,
            items: allItems,
            findings: allExecutionFindings
        )
    }
}

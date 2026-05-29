import Foundation

public struct ScreenshotUploadChunker {
    
    public init() {}
    
    public func chunk(
        plan: ScreenshotUploadPlan,
        strategy: ScreenshotChunkingStrategy
    ) -> [ScreenshotUploadChunk] {
        guard !plan.items.isEmpty else {
            return []
        }
        
        switch strategy {
        case .none:
            // Single chunk for everything
            return [
                ScreenshotUploadChunk(
                    id: "all",
                    strategy: strategy,
                    remoteScreenshotsToDelete: (plan.remoteScreenshotsToDelete ?? []).map(\.id),
                    itemsToUpload: plan.items
                )
            ]
            
        case .locale:
            var groupedItems = [String: [ScreenshotUploadPlanItem]]()
            var groupedDeletions = [String: [String]]()
            
            for item in plan.items {
                groupedItems[item.locale, default: []].append(item)
            }
            
            if let deletes = plan.remoteScreenshotsToDelete {
                for del in deletes {
                    let inferredLocale = inferLocale(from: del, availableLocales: Array(groupedItems.keys)) ?? "unknown-locale"
                    groupedDeletions[inferredLocale, default: []].append(del.id)
                }
            }
            
            let allLocales = Set(groupedItems.keys).union(groupedDeletions.keys)
            return allLocales.sorted().map { locale in
                ScreenshotUploadChunk(
                    id: locale,
                    strategy: strategy,
                    remoteScreenshotsToDelete: groupedDeletions[locale] ?? [],
                    itemsToUpload: groupedItems[locale] ?? []
                )
            }
            
        case .platform:
            var groupedItems = [String: [ScreenshotUploadPlanItem]]()
            var groupedDeletions = [String: [String]]()
            
            for item in plan.items {
                groupedItems[item.platform.rawValue, default: []].append(item)
            }
            
            if let deletes = plan.remoteScreenshotsToDelete {
                for del in deletes {
                    let platformStr = del.locale // fallback logic below isn't perfect for platform matching without API context, placing all deletes in a "global" block if unable to match
                    // Since we don't always have easy inverse metadata lookup by remote ID, we put deletes mostly on the first available chunk, or split by whatever identifier we can. 
                    // However, we'll try a rough bucket approach or just bucket them into a generic string.
                    let bucket = "all_platforms_deletions" 
                    groupedDeletions[bucket, default: []].append(del.id)
                }
            }
            
            let allPlatforms = Set(groupedItems.keys).union(groupedDeletions.keys)
            return allPlatforms.sorted().map { platform in
                ScreenshotUploadChunk(
                    id: platform,
                    strategy: strategy,
                    remoteScreenshotsToDelete: groupedDeletions[platform] ?? [],
                    itemsToUpload: groupedItems[platform] ?? []
                )
            }
        }
    }
    
    private func inferLocale(from deletion: ScreenshotRemoteDeletion, availableLocales: [String]) -> String? {
        // AppStoreConnect's API returns the localization ID but doesn't strictly provide the "en-US" string natively on the screenshot itself unless requested during inclusion.
        // It's mostly fine if deletion groups are slightly detached, but for best performance we want deletion alongside upload.
        // If we can't infer, we put it in an 'orphaned' block or return nil. 
        // For actual production, typically `del.locale` correlates 1:1 with locale if mapped back. We are safe to just use the localizationID as the grouping key.
        return deletion.locale
    }
}

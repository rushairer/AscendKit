sed -i '' 's/let platformStr = del.locale/let _ = del.locale/g' Sources/AscendKitCore/Screenshots/ScreenshotUploadChunker.swift

sed -i '' '/public func deleteAppScreenshot/i\
    public func uploadSingleScreenshot(\
        item: ScreenshotUploadPlanItem,\
        token: String\
    ) async throws -> ScreenshotUploadExecutionItem {\
        let fileURL = URL(fileURLWithPath: item.sourcePath)\
        let data = try ScreenshotImageSanitizer.opaquePNGData(from: fileURL)\
        let checksum = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()\
        let uploadFileName = fileURL.deletingPathExtension().lastPathComponent + ".png"\
        \
        let setID = try await findOrCreateScreenshotSet(\
            appStoreVersionLocalizationID: item.appStoreVersionLocalizationID,\
            displayType: item.displayType,\
            token: token\
        )\
        \
        let reservation = try await createAppScreenshotReservation(\
            appScreenshotSetID: setID,\
            fileName: uploadFileName,\
            fileSize: data.count,\
            token: token\
        )\
        try await uploadAssetParts(\
            uploadOperations: reservation.uploadOperations,\
            data: data\
        )\
        let commitResponse = try await commitAppScreenshot(\
            screenshotID: reservation.id,\
            checksum: checksum,\
            token: token\
        )\
        let deliveryState = try await pollAppScreenshotDeliveryState(\
            screenshotID: reservation.id,\
            token: token\
        )\
        return ScreenshotUploadExecutionItem(\
            planItemID: item.id,\
            appScreenshotSetID: setID,\
            appScreenshotID: reservation.id,\
            fileName: uploadFileName,\
            checksum: checksum,\
            assetDeliveryState: deliveryState.state,\
            assetDeliveryPollAttempts: deliveryState.attempts,\
            responses: [\
                reservation.response,\
                commitResponse\
            ]\
        )\
    }\
' Sources/AscendKitCore/ASC/ASCAPIClient.swift

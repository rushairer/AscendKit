sed -i '' -e '/let setID = try await findOrCreateScreenshotSet(/c\
        let setKey = "\(item.appStoreVersionLocalizationID)|\(item.displayType)"\
        let setID = try await findOrCreateScreenshotSet(\
' Sources/AscendKitCore/ASC/ASCAPIClient.swift

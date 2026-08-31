import Accelerate

public enum AudioLevelRMS {
    public static func rootMeanSquare(
        samples: UnsafeBufferPointer<Float>,
        frameCount: Int,
        frameStride: Int = 1
    ) -> Float? {
        guard frameCount > 0, frameStride > 0, samples.baseAddress != nil else {
            return nil
        }

        let (lastSampleIndex, overflow) = (frameCount - 1)
            .multipliedReportingOverflow(by: frameStride)
        guard !overflow, lastSampleIndex < samples.count else {
            return nil
        }

        var meanSquare: Float = 0
        vDSP_measqv(
            samples.baseAddress!,
            vDSP_Stride(frameStride),
            &meanSquare,
            vDSP_Length(frameCount)
        )

        guard meanSquare.isFinite else {
            return nil
        }

        return sqrt(max(0, meanSquare))
    }
}

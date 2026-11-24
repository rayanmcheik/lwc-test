public class VGTSQuotePDFScheduler {

    public static void scheduleJob() {

        System.schedule(
            'VGTS Quote PDF Detector',
            '0 0/5 * * * ?',
            new VGTSQuotePDFDetector()
        );
    }
}


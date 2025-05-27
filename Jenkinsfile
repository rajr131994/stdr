@Library("jenkins-library")_
 
rubyMicroservice {
    name = "services.connectors.s4hana_public_cloud"
    build = [
        updateVersionFile: true
    ]
	scans = [
        [
            type: "snyk", 
            enabled: true,
            parameters: [
                snykTarget: "services.connectors.s4hana_public_cloud",
                snykDetectionDepth: 40,
                failBuild: false,
                testSeverityThreshold: "high",
                monitorSeverityThreshold: "low",
                targetFramework: "ruby"
            ],
            container: [
                image: "bl-build-snyk",
                tag: "ruby-2.5-23.03.08.01"
            ]
        ],
        [
            type: "veracode",
            enabled: false,
            parameters: [
                createSandbox: false,
                sandboxName: "Jenkins Pipeline - Development",
                teamName: "FCM Team",
                targetFramework: "ruby"
            ],
            container: [
                image: "bl-build-veracode",
                pipelineScanTag: "pipeline-scan-23.07.31.00",
                uploadScanTag: "api-wrapper-java-23.07.21.00"
            ]
        ]
    ]
}

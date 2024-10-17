import SwiftUI
import CoreML

struct ContentView: View {
    @State private var selectedModel: String = ""
    @State private var modelList: [String] = []
    @State private var errorMessage: String = ""
    @State private var inferenceTime: String = "N/A"
    @State private var isRunning: Bool = false  // State to track if inference is running
    
    @State private var selectedHardware: MLComputeUnits = .all
    let hardwareOptions: [(String, MLComputeUnits)] = [
        ("CPU", .cpuOnly),
        ("CPU and GPU", .cpuAndGPU),
        ("All (Neural Engine, CPU, GPU)", .all)
    ]
    
    var body: some View {
        VStack {
            // Dropdown for model selection
            Picker("Select Model", selection: $selectedModel) {
                Text("No Model Selected").tag("")
                ForEach(modelList, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            
            // Display selected model
            if !selectedModel.isEmpty {
                Text("Selected Model: \(selectedModel)")
                    .padding()
            } else {
                Text("Please select a model.")
                    .padding()
            }
            
            // Dropdown for hardware selection
            Picker("Select Hardware", selection: $selectedHardware) {
                ForEach(hardwareOptions, id: \.1) { option in
                    Text(option.0).tag(option.1)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            
            // Button to start inference and measure time
            Button(action: {
                startInference()
            }) {
                Text(isRunning ? "Running..." : "Start Inference")
                    .padding()
                    .background(isRunning ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)  // Disable button while inference is running
            .padding()

            // Display inference time
            Text("Average Inference Time: \(inferenceTime) ms")
                .padding()
        }
        .onAppear {
            // Load available models when the view appears
            modelList = listAvailableModels()
        }
    }

    // Start inference and measure execution time
    func startInference() {
        guard !selectedModel.isEmpty else {
            errorMessage = "Please select a model."
            return
        }

        // Set isRunning to true to disable the button and show feedback
        isRunning = true
        errorMessage = ""

        // Load the selected model and set the hardware configuration
        let config = MLModelConfiguration()
        config.computeUnits = selectedHardware  // Set the selected hardware option

        guard let modelURL = Bundle.main.url(forResource: selectedModel, withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
            errorMessage = "Failed to load model."
            isRunning = false  // Re-enable button in case of error
            return
        }

        // Retrieve the input feature name dynamically
        guard let inputFeatureName = getInputFeatureName(for: model),
              let inputShape = getInputShape(for: model, featureName: inputFeatureName) else {
            errorMessage = "Could not retrieve input feature shape."
            isRunning = false  // Re-enable button in case of error
            return
        }

        // Create a random tensor based on the model's input shape
        let numRuns = 100
        let inputShapeArray = inputShape.map { NSNumber(value: $0) }  // Convert to NSNumber array for MLMultiArray
        guard let randomTensor = try? MLMultiArray(shape: inputShapeArray, dataType: .float32) else {
            errorMessage = "Failed to create random tensor."
            isRunning = false  // Re-enable button in case of error
            return
        }

        // Fill the tensor with random values
        for i in 0..<randomTensor.count {
            randomTensor[i] = NSNumber(value: Float.random(in: 0..<1))
        }

        // Measure inference time over multiple runs
        let start = Date()
        for _ in 1...numRuns {
            _ = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputFeatureName: randomTensor]))
        }
        let end = Date()  // End time after the loop

        // Calculate total time and average time per run
        let totalTime = end.timeIntervalSince(start)  // Total time in seconds

        // Calculate average time in milliseconds
        let averageTime = (totalTime / Double(numRuns)) * 1000  // Convert to milliseconds
        inferenceTime = String(format: "%.2f", averageTime)
        
        // Set isRunning to false to re-enable the button after inference
        isRunning = false
    }
}

// List all CoreML models available in the bundle
func listAvailableModels() -> [String] {
    let modelExtension = "mlmodelc"
    var modelNames: [String] = []
    
    // Search for all files with the extension ".mlmodelc" in the bundle
    let paths = Bundle.main.paths(forResourcesOfType: modelExtension, inDirectory: nil)
    
    if !paths.isEmpty {
        for path in paths {
            let modelName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            modelNames.append(modelName)
        }
    }
    
    return modelNames
}

// Retrieve the first input feature name from the model
func getInputFeatureName(for model: MLModel) -> String? {
    let inputDescriptions = model.modelDescription.inputDescriptionsByName
    return inputDescriptions.keys.first
}

// Retrieve the input shape for a specific feature name
func getInputShape(for model: MLModel, featureName: String) -> [Int]? {
    guard let inputDescription = model.modelDescription.inputDescriptionsByName[featureName],
          let multiArrayConstraint = inputDescription.multiArrayConstraint else {
        return nil
    }
    
    // Return the shape of the tensor (e.g., [1, 3, height, width])
    return multiArrayConstraint.shape.map { Int(truncating: $0) }
}

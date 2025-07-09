import SwiftUI

struct AIResponseView: View {
    @ObservedObject var openAIService: OpenAIService
    let transcribedText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("AI Assistant")
                .font(.headline)
            
            if !transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Message:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(transcribedText)
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Response:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    if openAIService.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating response...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    } else if let error = openAIService.lastError {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                Text("Error")
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                            }
                            
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !openAIService.lastResponse.isEmpty {
                        Text(openAIService.lastResponse)
                            .padding(12)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No response yet")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 200)
            }
            
            if !openAIService.isProcessing && !openAIService.lastResponse.isEmpty {
                Button("Clear Response") {
                    openAIService.clearResponse()
                }
                .foregroundColor(.blue)
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}
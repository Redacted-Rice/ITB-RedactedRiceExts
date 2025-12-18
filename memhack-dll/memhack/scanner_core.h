#ifndef SCANNER_CORE_H
#define SCANNER_CORE_H

#include <vector>
#include <cstdint>

// Forward declare for SafeMemory::Region
namespace SafeMemory {
	struct Region;
}

// Buffer size for scanning - use 64KB chunks for good cache performance
const size_t SCAN_BUFFER_SIZE = 65536;

// Rescan batching threshold - batch results within 4KB of each other
const size_t CHUNK_THRESHOLD = 4096;

// Maximum size for sequence searches (strings/byte arrays)
// This prevents excessive memory allocation and overlap calculations
// MUST be less than SCAN_BUFFER_SIZE for overlap logic to work correctly
const size_t MAX_SEQUENCE_SIZE = 4096;

// Compile-time assertion to ensure buffer is larger than max sequence
static_assert(SCAN_BUFFER_SIZE > MAX_SEQUENCE_SIZE,
              "SCAN_BUFFER_SIZE must be greater than MAX_SEQUENCE_SIZE for overlap to work");

// Float comparison epsilons
const float FLOAT_EPSILON = 0.0001f;
const double DOUBLE_EPSILON = 0.00000001;

// Scan types
enum class ScanType {
	EXACT,
	INCREASED,
	DECREASED,
	CHANGED,
	UNCHANGED,
	NOT
};

// Data types
enum class DataType {
	BYTE,
	INT,
	FLOAT,
	DOUBLE,
	BOOL,
	STRING, // Fixed length string. Does not check null term. If needed use byte array for now at least
	BYTE_ARRAY
};

union ScanValue {
	uint8_t byteValue;
	int32_t intValue;
	float floatValue;
	double doubleValue;
	bool boolValue;
};

// Single scan result
struct ScanResult {
	uintptr_t address;
	ScanValue value;
	ScanValue oldValue;
	bool hasOldValue;

	ScanResult() : address(0), hasOldValue(false) {
		value.doubleValue = 0.0;
		oldValue.doubleValue = 0.0;
	}
};

// Scanner instance
class Scanner {
public:
	Scanner(DataType dataType, size_t maxResults, size_t alignment);
	~Scanner();

	// Perform first scan of all heap memory
	// For sequence types, targetValue should be string or byte array data
	// For regular types, targetValue should be pointer to Value
	// valueSize is only used for sequence types
	void firstScan(ScanType scanType, const void* targetValue, size_t valueSize = 0);

	// Perform rescan filtering existing results
	// For sequence types, targetValue should be string or byte array data
	// For regular types, targetValue should be pointer to Value
	// valueSize is only used for sequence types
	void rescan(ScanType scanType, const void* targetValue, size_t valueSize = 0);

	// Reset scanner results to allow a new first scan
	void reset();

	// Read sequence bytes from memory (for NOT scans or debugging)
	bool readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const;

	// Getters
	bool isFirstScan() const { return firstScanDone == false; }
	DataType getDataType() const { return dataType; }
	size_t getDataTypeSize() const;
	ScanType getLastScanType() const { return lastScanType; }
	const std::vector<uint8_t>& getSearchSequence() const { return searchSequence; }
	size_t getSequenceSize() const { return searchSequence.size(); }
	bool isSequenceType() const;

	// Results
	const std::vector<ScanResult>& getResults() const { return results; }
	size_t getResultCount() const { return results.size(); }
	bool isMaxResultsReached() const { return maxResultsReached; }

	// Error handling
	void clearErrors() { errors.clear(); }
	const std::vector<std::string>& getErrors() const { return errors; }
	size_t getInvalidAddressCount() const { return invalidAddressCount; }
	bool hasError() const { return !errors.empty(); }

	// Timing
	bool checkTiming;
	void setCheckTiming(bool enabled) { checkTiming = enabled; }
	bool getCheckTiming() const { return checkTiming; }

private:
	DataType dataType;
	size_t maxResults;
	size_t alignment;
	std::vector<ScanResult> results;
	bool firstScanDone;
	bool maxResultsReached;

	// Sequence storage for sequence types (String and byte array)
	// This is separated from basic types because they are variable length and require
	// more storage and we handle the compare byte by byte as an optimization
	std::vector<uint8_t> searchSequence;

	// Track the last scan type used for determining if we need to
	// read values for sequence types when creating results
	ScanType lastScanType;

	// Error tracking (mutable so const methods can log errors)
	mutable std::vector<std::string> errors;
	// Track statistics for reporting (mutable so const methods can update)
	mutable size_t invalidAddressCount;

	// Set search sequence
	void setSearchSequence(const void* data, size_t size);

	// Compare values for basic types (int, float, etc)
	bool compareBasic(const void* a, const void* b) const;
	bool compareBasicGreater(const void* a, const void* b) const;
	bool compareBasicLess(const void* a, const void* b) const;

	// Compare sequence at memory address with stored searchSequence
	bool compareSequence(uintptr_t address) const;

	// Internal helpers for checkMatch
	bool checkSequenceMatch(const ScanResult& result, ScanType scanType) const;
	bool checkBasicMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Check if value matches scan criteria
	bool checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Common setup used by both firstScan and rescan
	bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize);

	// Initial scan helpers
	void scanRegion(uintptr_t base, size_t size, ScanType scanType, const void* targetValue);
	void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                       ScanType scanType, const void* targetValue);

	// Rescan helpers
	void rescanResultsInRegion(MEMORY_BASIC_INFORMATION& mbi, size_t& resultIdx,
	                           ScanType scanType, const void* targetValue,
	                           std::vector<ScanResult>& newResults, std::vector<uint8_t>& buffer);
	void rescanResultBatch(const std::vector<ScanResult>& oldResults, size_t batchStart, size_t batchEnd,
	                       uintptr_t chunkStart, size_t chunkSize, const uint8_t* buffer,
	                       ScanType scanType, const void* targetValue, std::vector<ScanResult>& newResults);
	void rescanResultDirect(const ScanResult& oldResult, uintptr_t regionEnd,
	                        ScanType scanType, const void* targetValue, std::vector<ScanResult>& newResults);

	// Read value from buffer at offset
	bool readValueFromBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                         ScanResult& result, uintptr_t actualAddress) const;

	// Read basic type value directly from memory for rescans
	bool readBasicValueDirect(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const;

	// Validate sequence directly from memory  for rescans
	// Does the full read & validation including
	bool validateSequenceDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const;

	// Safely copy memory with try/catch
	static bool safeCopyMemory(void* dest, const void* src, size_t size);

	// Reads value from buffer and checks if it matches (does NOT add to results)
	// Returns true if valid match, with result populated in outResult
	bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                           uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                           ScanResult& outResult) const;

	// Reads value directly from memory and checks if it matches (does NOT add to results)
	// Returns true if valid match, with result populated in outResult
	bool validateValueDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType,
	                         const void* targetValue, ScanResult& outResult) const;


	// Helper to report invalid address statistics if any
	void reportInvalidAddressStats();

	// Helper to add error message
	void addError(const char* format, ...) const;
};

#endif

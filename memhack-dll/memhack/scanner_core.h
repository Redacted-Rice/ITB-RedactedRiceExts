#ifndef SCANNER_CORE_H
#define SCANNER_CORE_H

#include <vector>
#include <cstdint>

// Forward declare for SafeMemory::Region
namespace SafeMemory {
	struct Region;
}

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

// Single scan result
struct ScanResult {
	uintptr_t address;
	union {
		uint8_t byteValue;
		int32_t intValue;
		float floatValue;
		double doubleValue;
		bool boolValue;
	} value;
	union {
		uint8_t byteValue;
		int32_t intValue;
		float floatValue;
		double doubleValue;
		bool boolValue;
	} oldValue;
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

	// Getters
	const std::vector<ScanResult>& getResults() const { return results; }
	size_t getResultCount() const { return results.size(); }
	bool isMaxResultsReached() const { return maxResultsReached; }
	bool isFirstScan() const { return firstScanDone == false; }
	DataType getDataType() const { return dataType; }
	size_t getInvalidAddressCount() const { return invalidAddressCount; }
	ScanType getLastScanType() const { return lastScanType; }

	// Error handling
	const std::vector<std::string>& getErrors() const { return errors; }
	bool hasError() const { return !errors.empty(); }
	void clearErrors() { errors.clear(); }

	// Report invalid address statistics if any
	void reportInvalidAddressStats();

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

	// Helper to add error message
	void addError(const char* format, ...) const;

	// Compare values for basic types (int, float, etc)
	bool compareBasic(const void* a, const void* b) const;
	bool compareBasicGreater(const void* a, const void* b) const;
	bool compareBasicLess(const void* a, const void* b) const;

	// Compare sequence at memory address with stored searchSequence
	bool compareSequence(uintptr_t address) const;

	// Check if value matches scan criteria
	bool checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Internal helpers for checkMatch
	bool checkSequenceMatch(const ScanResult& result, ScanType scanType) const;
	bool checkBasicMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Common setup used by both firstScan and rescan
	bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize);

	// Set search sequence
	void setSearchSequence(const void* data, size_t size);

	// Scan single memory region
	void scanRegion(void* base, size_t size, ScanType scanType, const void* targetValue);

	// Find region containing address (returns nullptr if not found)
	const SafeMemory::Region* findRegionContainingAddress(uintptr_t address, const std::vector<SafeMemory::Region>& regions) const;

	// Read value at address, checking bounds against region being scanned
	bool readValueInRegion(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const;

	// Read value at address, verifying against current heap regions
	bool readValueWithVerification(uintptr_t address, const std::vector<SafeMemory::Region>& regions, ScanResult& result) const;


	// Get data type size (for sequence types, returns sequence size)
	size_t getDataTypeSize() const;

	// Check if data type is a sequence type (STRING or BYTE_ARRAY)
	bool isSequenceType() const;

	// Read sequence bytes from memory (for NOT scans or debugging)
	bool readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const;

	// Get the search sequence (for returning in EXACT scan results)
	const std::vector<uint8_t>& getSearchSequence() const { return searchSequence; }
	size_t getSequenceSize() const { return searchSequence.size(); }
};

#endif

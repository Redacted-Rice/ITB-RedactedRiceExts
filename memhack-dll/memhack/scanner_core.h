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
	BOOL
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

	// Perform first scan
	void firstScan(ScanType scanType, const void* targetValue);

	// Perform rescan on existing results
	void rescan(ScanType scanType, const void* targetValue);

	// Reset scanner
	void reset();

	// Getters
	const std::vector<ScanResult>& getResults() const { return results; }
	size_t getResultCount() const { return results.size(); }
	bool isMaxResultsReached() const { return maxResultsReached; }
	bool isFirstScan() const { return firstScanDone == false; }
	DataType getDataType() const { return dataType; }
	size_t getInvalidAddressCount() const { return invalidAddressCount; }

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

	// Error tracking (mutable so const methods can log errors)
	mutable std::vector<std::string> errors;
	// Track statistics for reporting (mutable so const methods can update)
	mutable size_t invalidAddressCount;

	// Helper to add error message
	void addError(const char* format, ...) const;

	// Compare values based on data type
	bool compareEqual(const void* a, const void* b) const;
	bool compareGreater(const void* a, const void* b) const;
	bool compareLess(const void* a, const void* b) const;

	// Check if value matches scan criteria
	bool checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Scan single memory region
	void scanRegion(void* base, size_t size, ScanType scanType, const void* targetValue);

	// Find region containing address (returns nullptr if not found)
	const SafeMemory::Region* findRegionContainingAddress(uintptr_t address, const std::vector<SafeMemory::Region>& regions) const;

	// Read value at address, checking bounds against region being scanned
	bool readValueInRegion(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const;

	// Read value at address, verifying against current heap regions
	bool readValueWithVerification(uintptr_t address, const std::vector<SafeMemory::Region>& regions, ScanResult& result) const;


	// Get data type size
	size_t getDataTypeSize() const;
};

#endif

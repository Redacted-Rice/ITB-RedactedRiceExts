#ifndef SCANNER_STRUCT_H
#define SCANNER_STRUCT_H

#include "scanner_base.h"
#include "scanner_basic.h"
#include "scanner_sequence.h"
#include <windows.h>


// Maximum size for struct searches
// This prevents excessive memory allocation and overlap calculations
// MUST be less than SCAN_BUFFER_SIZE for overlap logic to work correctly
const size_t MAX_STRUCT_SIZE = 8192;

// Compile-time assertion to ensure buffer is larger than max struct
static_assert(SCAN_BUFFER_SIZE > MAX_STRUCT_SIZE,
              "SCAN_BUFFER_SIZE must be greater than MAX_STRUCT_SIZE for overlap to work");
              
// Scanner implementation for struct types
// Uses memchr-based keyed value as basw for search
class StructScanner : public Scanner {
public:
    // dont use inheritence so they are easily separated and dont have ti deal with delegation
    class StructFieldBasic : public StructField {
        int offset;
        BasicScanner::DataType type;
        ScanValue val;
        
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;
    	
    	StructFieldBasic(int offset, BasicScanner::DataType type, ScanValue val);
    	virtual ~StructFieldBasic() {}
    	
        virtual bool compare(void* memoryAddr) const;
    };
    
    class StructFieldSequence : public StructField {
        int offset;
        std::vector<uint8_t, ScannerAllocator<uint8_t>> val;
        
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;
    	
    	StructFieldSequence(int offset, uint8_t* data, size_t size);
    	virtual ~StructFieldSequence() {}
    	
        virtual bool compare(void* memoryAddr) const;
    };

    class StructSearch {
        uint8_t searchKey;
        std::vector<StructField, ScannerAllocator<StructFieldBasic>> basicFields;
        std::vector<StructField, ScannerAllocator<StructFieldSequence>> sequenceFields;
        size_t sizeBeforeKey;
        size_t sizeAfterKey;
        
    	// Override new/delete to allocate from scanner heap
    	// This ensures the Scanner and data can be excluded from scans
    	static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;
    	
    	StructSearch(uint8_t* key) : searchKey(key), sizeBeforeKey(0), sizeAfterKey(0)
    	virtual ~StructSearch() {};
    	
    	void adjustSizes(offset, length) {
    	    if (offset < 0 && -offset > sizeBeforeKey) {
                sizeBeforeKey = -offset;
            }
            if (offset + length > sizeAfterKey) {
                sizeAfterKey = offset + length;
            }
    	}
    	
        void addField(int offset, BasicScanner::DataType type, ScanValue val) {
            basicFields.emplace_back(offset, type, val);
            adjustSizes(offset, BasicScanner::getDataTypeSize(type));
        };
        
        void addField(int offset, uint8_t* data, size_t size) {
            basicFields.emplace_back(offset, data, size);
            adjustSizes(offset, size);
        };
        
        int getSize() const { return sizeBeforeKey + sizeAfterKey; }
    };

	StructScanner(size_t maxResults, size_t alignment);
	virtual ~StructScanner();
	
	static StructScanner* create(DataType dataType, size_t maxResults, size_t alignment);
	
	void setSearchStruct(const StructSearch& targetStruct);

protected:
	// Setup hook - store/update search sequence
	virtual bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) override;

	// only allow EXACT for first scan
	virtual bool validateFirstScanType(ScanType scanType) override;

	// Chunk scanning - sequence scanner implements memchr based scan
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue,
	                               std::vector<ScanResult>& localResults, size_t maxLocalResults) override;

	// Rescan pure virtuals - sequence scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// Getters
	virtual size_t getDataTypeSize() const override;

private:
	// Sequence storage
	StructSearch searchStruct;

	// Sequence specific helpers
	bool compare(const uint8_t* dataToCompare) const;
	bool checkMatch(const uint8_t* dataToCompare, ScanType scanType) const;
	bool validateStructDirect(uintptr_t address, uintptr_t regionEnd) const;
};

#endif

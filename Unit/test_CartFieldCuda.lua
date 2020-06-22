-- Gkyl ------------------------------------------------------------------------
--
-- Test for fields on cartesian grids on CUDA device
--    _______     ___
-- + 6 @ |||| # P ||| +
--------------------------------------------------------------------------------
--
-- Don't do anything if we were not built with CUDA.
if GKYL_HAVE_CUDA == false then
   print("**** Can't run CUDA tests without CUDA enabled GPUs!")
   return 0
end

local Alloc = require "Lib.Alloc"
local Basis = require "Basis"
local DataStruct = require "DataStruct"
local Grid = require "Grid"
local Time = require "Lib.Time"
local Unit = require "Unit"
local cuda = require "Cuda.RunTime"
local cudaAlloc = require "Cuda.Alloc"
local ffi = require "ffi"

local assert_equal = Unit.assert_equal
local assert_close = Unit.assert_close
local stats = Unit.stats

ffi.cdef [[
  void unit_showFieldRange(GkylCartField_t *f, double *g);
  void unit_showFieldGrid(GkylCartField_t *f);
  void unit_readAndWrite(int numBlocks, int numThreads, GkylCartField_t *f, GkylCartField_t *res);
  void unit_readAndWrite_shared(int numBlocks, int numThreads, int sharedSize, GkylCartField_t *f, GkylCartField_t *res);
  void unit_readAndWrite_shared_offset(int numBlocks, int numThreads, int sharedSize, GkylCartField_t *f, GkylCartField_t *res);
]]

local function createGrid(lo,up,nCells)
   local gridOut = Grid.RectCart {
      lower = lo,
      upper = up,
      cells = nCells,
   }
   return gridOut
end

local function createBasis(dim, pOrder, bKind)
   local basis
   if (bKind=="Ser") then
      basis = Basis.CartModalSerendipity { ndim = dim, polyOrder = pOrder }
   elseif (bKind=="Max") then
      basis = Basis.CartModalMaxOrder { ndim = dim, polyOrder = pOrder }
   elseif (bKind=="Tensor") then
      basis = Basis.CartModalTensor { ndim = dim, polyOrder = pOrder }
   else
      assert(false,"Invalid basis")
   end
   return basis
end

local function createField(grid, basis, deviceCopy, ghosts, isP0, vComp)
   vComp = vComp or 1
   if ghost then
      ghostCells = {1, 1}
   else
      ghostCells = {0, 0}
   end
   if isP0 then
      numBasisElements = 1
   else
      numBasisElements = basis:numBasis()*vComp
   end
   local fld = DataStruct.Field {
      onGrid           = grid,
      numComponents    = numBasisElements,
      ghost            = ghostCells,
      createDeviceCopy = deviceCopy,
      metaData = {
         polyOrder = basis:polyOrder(),
         basisType = basis:id()
      },
   }
   return fld
end

function test_1()
   local grid = Grid.RectCart {
      lower = {0.0},
      upper = {1.0},
      cells = {1000},
   }
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = 3,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   local field2 = DataStruct.Field {
      onGrid = grid,
      numComponents = 3,
      ghost = {1, 1},
      createDeviceCopy = true,
   }

   local localRange = field:localRange()
   local indexer = field:indexer()
   for i = localRange:lower(1), localRange:upper(1) do
      local fitr = field:get(indexer(i))
      fitr[1] = i+1
      fitr[2] = i+2
      fitr[3] = i+3
   end

   -- copy stuff to device
   local err = field:copyHostToDevice()
   local err2 = field2:copyHostToDevice()
   assert_equal(0, err, "Checking if copy to device worked")
   assert_equal(0, err2, "Checking if copy to device worked")

   field:deviceScale(-0.5)
   field:deviceAbs()
   field2:deviceClear(1.0)
   field:deviceAccumulate(2.0, field2, 0.5, field2)
   field:copyDeviceToHost()

   if GKYL_HAVE_CUDA then
      for i = localRange:lower(1), localRange:upper(1) do
	 local fitr = field:get(indexer(i))
	 assert_equal(0.5*(i+1)+2.5, fitr[1], "Checking deviceScale")
	 assert_equal(0.5*(i+2)+2.5, fitr[2], "Checking deviceScale")
	 assert_equal(0.5*(i+3)+2.5, fitr[3], "Checking deviceScale")
      end
   end
end

function test_2()
   local grid = Grid.RectCart {
      lower = {0.0},
      upper = {1.0},
      cells = {20},
   }
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = 3,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   field:clear(1.0)
   field:copyHostToDevice()
   --ffi.C.unit_showFieldRange(field._onDevice, field._devAllocData:data())
   --ffi.C.unit_showFieldGrid(field._onDevice)
end

-- read a CartField, and then write it to a result CartField (basically a copy via a kernel)
function test_3()
   local grid = Grid.RectCart {
      cells = {8, 9},
   }
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = 32,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   field:clear(-1)
   local indexer = field:genIndexer()
   for idx in field:localExtRangeIter() do
      local fitr = field:get(indexer(idx))
      fitr[1] = 5*idx[1] + 2*idx[2]+1
      fitr[2] = 5*idx[1] + 2*idx[2]+2
      fitr[3] = 5*idx[1] + 2*idx[2]+3
   end
   field:copyHostToDevice()
   local result = DataStruct.Field {
      onGrid = grid,
      numComponents = 32,
      ghost = {1, 1},
      createDeviceCopy = true,
   }

   local numCellsLocal = field:localRange():volume()
   local numThreads = 64
   local numBlocks = math.ceil(numCellsLocal/numThreads)
   ffi.C.unit_readAndWrite(numBlocks, numThreads, field._onDevice, result._onDevice)
   result:copyDeviceToHost()

   for idx in field:localRangeIter() do
      local fitr = field:get(indexer(idx))
      local ritr = result:get(indexer(idx))
      for i = 1, field:numComponents() do
         assert_equal(fitr[i], ritr[i], string.format("readAndWrite test: incorrect element at index %d, component %d", indexer(idx), i))
      end
   end
end

function test_4()
   local grid = Grid.RectCart {
      cells = {8, 8},
   }
   local nComp = 32
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = nComp,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   field:clear(-1)
   local indexer = field:genIndexer()
   for idx in field:localRangeIter() do
      local fitr = field:get(indexer(idx))
      fitr[1] = 5*idx[1] + 2*idx[2]+1
      fitr[2] = 5*idx[1] + 2*idx[2]+2
      fitr[3] = 5*idx[1] + 2*idx[2]+3
   end
   field:copyHostToDevice()
   local result = DataStruct.Field {
      onGrid = grid,
      numComponents = nComp,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   result:clear(10000)
   result:copyHostToDevice()

   local numCellsLocal = field:localRange():volume()
   local numThreads = 64
   -- check that numThreads is evenly divisible by numComponents
   assert(numThreads % nComp == 0, string.format("\nshared memory implementation currently requires numThreads (%d) evenly divisible by numComponents (%d)", numThreads, nComp))
   -- check that number of cells in last dimension is evenly divisible by numThreads/numComponents
   assert(grid:numCells(grid:ndim()) % (numThreads/nComp) == 0, string.format("\nshared memory implementation currently requires number of cells in last dimension (%d) to be evenly divisible by numThreads/numComponents (%d/%d=%d)", grid:numCells(grid:ndim()), numThreads, nComp, numThreads/nComp))
   local numBlocks = math.ceil(numCellsLocal/numThreads)
   local sharedSize = numThreads*field:numComponents()
   ffi.C.unit_readAndWrite_shared(numBlocks, numThreads, sharedSize, field._onDevice, result._onDevice)
   local err = cuda.DeviceSynchronize()
   assert_equal(0, err, "cuda error")
   result:copyDeviceToHost()

   for idx in field:localRangeIter() do
      local fitr = field:get(indexer(idx))
      local ritr = result:get(indexer(idx))
      for i = 1, field:numComponents() do
         assert_equal(fitr[i], ritr[i], string.format("readAndWrite_shared test: incorrect element at index %d, component %d", indexer(idx)-1, i))
      end
   end
end

function test_5()
   local grid = Grid.RectCart {
      cells = {8, 8},
   }
   local nComp = 32
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = nComp,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   field:clear(-1)
   local indexer = field:genIndexer()
   for idx in field:localRangeIter() do
      local fitr = field:get(indexer(idx))
      fitr[1] = 5*idx[1] + 2*idx[2]+1
      fitr[2] = 5*idx[1] + 2*idx[2]+2
      fitr[3] = 5*idx[1] + 2*idx[2]+3
   end
   field:copyHostToDevice()
   local result = DataStruct.Field {
      onGrid = grid,
      numComponents = nComp,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   result:clear(10000)
   result:copyHostToDevice()

   local numCellsLocal = field:localRange():volume()
   local numThreads = 32
   -- check that numThreads is evenly divisible by numComponents
   assert(numThreads % nComp == 0, string.format("\nshared memory implementation currently requires numThreads (%d) evenly divisible by numComponents (%d)", numThreads, nComp))
   -- check that number of cells in last dimension is evenly divisible by numThreads/numComponents
   assert(grid:numCells(grid:ndim()) % (numThreads/nComp) == 0, string.format("\nshared memory implementation currently requires number of cells in last dimension (%d) to be evenly divisible by numThreads/numComponents (%d/%d=%d)", grid:numCells(grid:ndim()), numThreads, nComp, numThreads/nComp))
   local numBlocks = math.ceil(numCellsLocal/numThreads)
   local sharedSize = 80*field:numComponents()
   ffi.C.unit_readAndWrite_shared_offset(numBlocks, numThreads, sharedSize, field._onDevice, result._onDevice)
   local err = cuda.DeviceSynchronize()
   assert_equal(0, err, "cuda error")
   result:copyDeviceToHost()
   local ndim = grid:ndim()

   for idx in field:localRangeIter() do
      local fitr = field:get(indexer(idx))
      idx[ndim] = idx[ndim]+1
      local ritr = result:get(indexer(idx))
      for i = 1, field:numComponents() do
         assert_equal(fitr[i], ritr[i], string.format("readAndWrite_shared_offset test: incorrect element at index %d, component %d", indexer(idx)-1, i))
      end
   end
end

local function test_deviceReduce(nIter, reportTiming)
   -- Test the reduceDevice method.
   local pOrder        = 1
   local basis         = "Ser"
   local phaseLower    = {0.0, -6.0}
   local phaseUpper    = {1.0,  6.0}
   local phaseNumCells = {8100, 531}
   
   -- Phase-space grid, basis and data field.
   local phaseGrid  = createGrid(phaseLower, phaseUpper, phaseNumCells)
   local phaseBasis = createBasis(phaseGrid:ndim(), pOrder, basis)
   local field      = createField(phaseGrid, phaseBasis, true, true, false)
   -- Initialize field to random numbers.
   math.randomseed(1000*os.time())
   local fldRange = field:localRange()
   local fldIdxr  = field:genIndexer()
   for idx in fldRange:rowMajorIter() do
      local fldItr = field:get(fldIdxr( idx ))
      for k = 1, field:numComponents() do
         fldItr[k] = math.random()
      end
   end
   field:copyHostToDevice()

   -- Get the maximum, minimum and sum on the CPU (for reference).
   local maxVal, minVal, sumVal = field:reduce("max"), field:reduce("min"), field:reduce("sum")

   local d_maxVal = cudaAlloc.Double(field:numComponents())
   local d_minVal = cudaAlloc.Double(field:numComponents())
   local d_sumVal = cudaAlloc.Double(field:numComponents())
   
   local tmStart = Time.clock()
   for i = 1, nIter do
      field:deviceReduce("max",d_maxVal)
      field:deviceReduce("min",d_minVal)
      field:deviceReduce("sum",d_sumVal)
   end
   local err = cuda.DeviceSynchronize()
   if reportTiming then
      local totalGpuTime = (Time.clock()-tmStart)
      print(string.format("Total GPU time for %d calls = %f s   (average = %f s per call)", nIter*3, totalGpuTime, totalGpuTime/(3*nIter)))
   end
   
   -- Test that the value found is correct.
   local maxVal_gpu = Alloc.Double(field:numComponents())
   local minVal_gpu = Alloc.Double(field:numComponents())
   local sumVal_gpu = Alloc.Double(field:numComponents())
   local err = d_maxVal:copyDeviceToHost(maxVal_gpu)
   local err = d_minVal:copyDeviceToHost(minVal_gpu)
   local err = d_sumVal:copyDeviceToHost(sumVal_gpu)
   
   
   for k = 1, field:numComponents() do
      assert_equal(maxVal[k], maxVal_gpu[k], "Checking max reduce of CartField on GPU.")
      assert_equal(minVal[k], minVal_gpu[k], "Checking min reduce of CartField on GPU.")
      assert_close(sumVal[k], sumVal_gpu[k], 1.e-12*sumVal_gpu[k], "Checking sum reduce of CartField on GPU.")
   end
   
   d_maxVal:delete()
   d_minVal:delete()
   d_sumVal:delete()
   maxVal_gpu:delete()
   minVal_gpu:delete()
   sumVal_gpu:delete()
end

-- This test synchronizes periodic boundary conditions on a single GPU (performs a copy from the skin cells to the ghost cells).
function test_6()
   
   local grid = Grid.RectCart {
      lower = {0.0, 0.0},
      upper = {1.0, 1.0},
      cells = {10, 10},
      periodicDirs = {1, 2},
   }
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = 1,
      ghost = {1, 1},
      createDeviceCopy = true,
   }
   field:clear(10.5)

   -- set corner cells
   local indexer = field:indexer()
   local fItr = field:get(indexer(1,1)); fItr[1] = 1.0
   fItr = field:get(indexer(10,1)); fItr[1] = 2.0
   fItr = field:get(indexer(1,10)); fItr[1] = 3.0
   fItr = field:get(indexer(10,10)); fItr[1] = 4.0

   -- copy stuff to device
   local err = field:copyHostToDevice()
   assert_equal(0, err, "Checking if copy to device worked")

   -- synchronize periodic directions on device
   field:devicePeriodicCopy() -- sync field

   -- copy data back for checking.
   field:copyDeviceToHost()

   -- check if periodic dirs are sync()-ed properly
   local fItr = field:get(indexer(11,1))
   assert_equal(1.0, fItr[1], "Checking non-corner periodic sync")
   local fItr = field:get(indexer(11,10))
   assert_equal(3.0, fItr[1], "Checking non-corner periodic sync")
   local fItr = field:get(indexer(0,1))
   assert_equal(2.0, fItr[1], "Checking non-corner periodic sync")
   local fItr = field:get(indexer(0,10))
   assert_equal(4.0, fItr[1], "Checking non-corner periodic sync")

end

function test_7()
   local grid = Grid.RectCart {
      lower = {0.0},
      upper = {1.0},
      cells = {1000},
   }
   local field = DataStruct.Field {
      onGrid = grid,
      numComponents = 8,
      ghost = {1, 2},
      createDeviceCopy = true,
   }
   local field2 = DataStruct.Field {
      onGrid = grid,
      numComponents = 3,
      ghost = {1, 2},
      createDeviceCopy = true,
   }

   local localRange = field:localRange()
   local indexer = field:indexer()
   for i = localRange:lower(1), localRange:upper(1) do
      local fitr = field:get(indexer(i))
      fitr[1] = i+1
      fitr[2] = i+2
      fitr[3] = i+3
      fitr[4] = i+4
      fitr[5] = i+5
      fitr[6] = i+6
      fitr[7] = i+7
      fitr[8] = i+8
   end

   -- copy stuff to device
   local err = field:copyHostToDevice()
   local err2 = field2:copyHostToDevice()
   assert_equal(0, err, "Checking if copy to device worked")
   assert_equal(0, err2, "Checking if copy to device worked")

   field:deviceScale(-0.5)
   field:deviceAbs()
   field2:deviceClear(1.0)
   field:deviceAccumulateOffset(2.0, field2, 0, 0.5, field2, 5)
   field:copyDeviceToHost()

   if GKYL_HAVE_CUDA then
      for i = localRange:lower(1), localRange:upper(1) do
	 local fitr = field:get(indexer(i))
	 assert_equal(0.5*(i+1)+2.0, fitr[1], "Checking deviceScale")
	 assert_equal(0.5*(i+2)+2.0, fitr[2], "Checking deviceScale")
	 assert_equal(0.5*(i+3)+2.0, fitr[3], "Checking deviceScale")
	 assert_equal(0.5*(i+4), fitr[4], "Checking deviceScale")
	 assert_equal(0.5*(i+5), fitr[5], "Checking deviceScale")
	 assert_equal(0.5*(i+6)+0.5, fitr[6], "Checking deviceScale")
	 assert_equal(0.5*(i+7)+0.5, fitr[7], "Checking deviceScale")
	 assert_equal(0.5*(i+8)+0.5, fitr[8], "Checking deviceScale")
      end
   end
end

test_1()
test_2()
test_3()
test_4()
test_5()
test_deviceReduce(1, false)

test_6()
test_7()

if stats.fail > 0 then
   print(string.format("\nPASSED %d tests", stats.pass))
   print(string.format("**** FAILED %d tests", stats.fail))
else
   print(string.format("PASSED ALL %d tests!", stats.pass))
end

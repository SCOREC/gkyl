-- Gkyl ------------------------------------------------------------------------
--
-- Projections base object.
--
--    _______     ___
-- + 6 @ |||| # P ||| +
--------------------------------------------------------------------------------

local Proto = require "Lib.Proto"

-- Empty shell species base class.
local ProjectionBase = Proto()

-- Functions that must be defined by subclasses.
function ProjectionBase:init(tbl) end
function ProjectionBase:fullInit(appTbl) end
function ProjectionBase:set() end
function ProjectionBase:createCouplingSolver() end

return ProjectionBase


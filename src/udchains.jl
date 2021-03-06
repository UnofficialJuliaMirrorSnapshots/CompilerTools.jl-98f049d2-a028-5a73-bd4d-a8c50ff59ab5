#=
Copyright (c) 2015, Intel Corporation
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
THE POSSIBILITY OF SUCH DAMAGE.
=#

module UDChains

import ..DebugMsg
DebugMsg.init()

using CompilerTools

import Base.show

"""
Contains the UDchains for one basic block.
"""
type UDInfo
    live_in  :: Dict{Symbol,Set}
    live_out :: Dict{Symbol,Set}

    function UDInfo()
        new(Dict{Symbol,Set}(), Dict{Symbol,Set}())
    end
end

"""
Get the set of definition blocks reaching this block for a given symbol "s".
"""
function getOrCreate(live :: Dict{Symbol, Set}, s :: Symbol)
    if !haskey(live, s)
        live[s] = Set()
    end
    return live[s]
end

"""
Get the UDInfo for a specified basic block "bb" or create one if it doesn't already exist.
"""
function getOrCreate(udchains :: Dict{CompilerTools.LivenessAnalysis.BasicBlock,UDInfo} , bb :: CompilerTools.LivenessAnalysis.BasicBlock)
    if !haskey(udchains, bb)
        udchains[bb] = UDInfo()
    end
    return udchains[bb]
end

"""
Print the set part of a live in or live out dictiononary in a nice way if the debug level is set high enough.
"""
function printSet(level, s)
    for j in s
        if typeof(j) == CompilerTools.LivenessAnalysis.BasicBlock
            dprint(level, " ", j.label)
        else
            dprint(level, " ", j)
        end
    end
end

"""
Print a live in or live out dictionary in a nice way if the debug level is set high enough.
"""
function printLabels(level, dict)
    for i in dict
       dprint(level, "\tSymbol: ", i[1], " From:")
       printSet(level, i[2])
       dprintln(level,"")
    end
end

"""
Print UDChains in a nice way if the debug level is set high enough.
"""
function printUDInfo(level, ud)
    for i in ud
        dprintln(level, i[1].label, " Live In:")
        printLabels(level, i[2].live_in)
        dprintln(level, i[1].label, " Live Out:")
        printLabels(level, i[2].live_out)
    end
end

"""
Get the Use-Definition chains at a basic block level given LivenessAnalysis.BlockLiveness as input in "bl".
"""
function getUDChains(bl :: CompilerTools.LivenessAnalysis.BlockLiveness)
    udchains = Dict{CompilerTools.LivenessAnalysis.BasicBlock,UDInfo}()

    @dprintln(3,"getUDChains: bl = ", bl)

    body_order = CompilerTools.LivenessAnalysis.getBbBodyOrder(bl)
    changed = true
    # Iterate until nothing changes.
    while changed
        @dprintln(3,"getUDChains: main loop")
        changed = false
        # For each basic block from beginning to end.
        for i = 1:length(body_order)
            bb = bl.basic_blocks[body_order[i]]
            # Get the UDChain info for this basic block.
            udinfo = getOrCreate(udchains, bb)
            @dprintln(3,"getUDChains: bb = ", bb, " udinfo = ", udinfo)

            for li in bb.live_in
                # Get the current set of blocks from which this symbol could be defined and reach here.
                li_set = getOrCreate(udinfo.live_in, li)
                @dprint(3,"getUDChains: li = ", li, " li_set = ")
                printSet(3,li_set)
                @dprintln(3,"")
 
                if isempty(bb.preds)
                    @dprintln(3,"getUDChains: no preds")
                    # Must be the starting block.
                    # Use "nothing" to represent the parameter set.
                    if !in(nothing, li_set)
                        @dprintln(3,"getUDChains: added nothing to li_set")
                        push!(li_set, nothing)
                        changed = true
                    end
                else
                    # Non-starting block.
                    for pred in bb.preds
                        pred_udinfo = getOrCreate(udchains, pred)
                        pred_lo_set = getOrCreate(pred_udinfo.live_out, li)
                        #@dprint(3,"getUDChains: pred = ", pred.label, " pred_udinfo = ", pred_udinfo, " pred_lo_set = ", pred_lo_set)
                        @dprint(3,"getUDChains: pred = ", pred.label, " pred_lo_set = ", pred_lo_set)
                        printSet(3,li_set)
                        @dprintln(3,"")
                        for pred_lo in pred_lo_set
                            if !in(pred_lo, li_set)
                                push!(li_set, pred_lo)
                                changed = true
                                @dprintln(3,"getUDChains: added ", pred_lo, " to li_set = ", li_set)
                            end
                        end
                    end
                end
            end

            # For each symbol live_out of this block.
            for lo in bb.live_out
                # Get the current set of blocks from which this symbol could be defined and reach here.
                lo_set = getOrCreate(udinfo.live_out, lo)
                @dprint(3,"getUDChains: lo = ", lo, " lo_set = ")
                printSet(3,lo_set)
                @dprintln(3,"")

                # If this live out was defined in this block...
                if in(lo, bb.def)
                    @dprintln(3,"getUDChains: lo def in block")
                    # ... then add this block to udchain for this symbol.
                    if !in(bb, lo_set)
                        @dprintln(3,"getUDChains: adding bb to lo_set")
                        push!(lo_set, bb)
                        changed = true
                    end 
                else
                    # Not defined in this block so must be live_in.
                    li_set = getOrCreate(udinfo.live_in, lo)
                    @dprintln(3,"getUDChains: not def in block so using li_set = ", li_set)
                    for li_bb in li_set
                        if !in(li_bb, lo_set)
                            @dprintln(3,"getUDChains: adding ", typeof(li_bb)==CompilerTools.LivenessAnalysis.BasicBlock ? li_bb.label : li_bb, " to lo_set")
                            push!(lo_set, li_bb)
                            changed = true
                        end 
                    end
                end
            end
        end 
    end

    return udchains
end

end

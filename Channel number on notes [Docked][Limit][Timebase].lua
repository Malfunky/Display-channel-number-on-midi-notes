  
dcc=0 
--inspectorheight =  62 
Fontsize = 15 

sectionID = 32060 -- midi editor
local bs = reaper.SetToggleCommandState(sectionID ,({reaper.get_action_context()})[4],1)  

LICEFont = reaper.JS_LICE_CreateFont() 
local color = 0xFFFFFF -- 0xRRGGBB
reaper.JS_LICE_SetFontColor( LICEFont,   color)  
bitmaps = {}
 

function ConvertCCTypeChunkToAPI(lane) --sader magic
    tLanes = {[ -1] = 0x200, -- Velocity
                    [128] = 0x201, -- Pitch
                    [129] = 0x202, -- Program select
                    [130] = 0x203, -- Channel pressure
                    [131] = 0x204, -- Bank/program
                    [132] = 0x205, -- Text
                    [133] = 0x206, -- Sysex
                    [167] = 0x207, -- Off velocity
                    [166] = 0x208, -- Notation
                    [ -2] = 0x210, -- Media Item lane
                   }    
    if type(lane) == "number" and 134 <= lane and lane <= 165 then 
        return (lane + 122) -- 14 bit CC range from 256-287 in API
    else 
        return (tLanes[lane] or lane) -- If 7bit CC, number remains the same
    end
end 

timerun = 0
function readfromchunk()   -- This is mostly based on Julian Saders midiscripts 
  timerun = timerun + 1
  timestart = reaper.time_precise()
  tME_Lanes = {}  

  midiview  = reaper.JS_Window_FindChildByID(hwnd, 1001)
    
  item = reaper.GetMediaItemTake_Item(take) 
  _, chunk = reaper.GetItemStateChunk( item,"",1)  
    ----------------------------------------------------------------- 
  takeNum = reaper.GetMediaItemTakeInfo_Value(take, "IP_TAKENUMBER")
  takeChunkStartPos = 1
  for t = 1, takeNum do
        takeChunkStartPos = chunk:find("\nTAKE[^\n]-\nNAME", takeChunkStartPos+1)
        if not takeChunkStartPos then 
            reaper.MB("Could not find the active take's part of the item state chunk.", "ERROR", 0) 
            return false
        end
  end 
  takeChunkEndPos = chunk:find("\nTAKE[^\n]-\nNAME", takeChunkStartPos+1)
  activeTakeChunk = chunk:sub(takeChunkStartPos, takeChunkEndPos) 
     
  ME_LeftmostTick, ME_HorzZoom, ME_TopPitch, ME_PixelsPerPitch = 
  activeTakeChunk:match("\nCFGEDITVIEW (%S+) (%S+) (%S+) (%S+)") 
  ME_LeftmostTick,  ME_HorzZoom , ME_TopPitch , ME_PixelsPerPitch = 
  tonumber(ME_LeftmostTick),tonumber(ME_HorzZoom),tonumber(ME_TopPitch),tonumber(ME_PixelsPerPitch)
  activeChannel, ME_Docked, ME_TimeBase = activeTakeChunk:match("\nCFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ (%S+)")
  _,  hwnd_x,  hwnd_y = reaper.BR_Win32_GetWindowRect( hwnd) 
  tbase= tonumber(ME_TimeBase) 
  topvisiblepitch = 127 - ME_TopPitch 
  if ME_Docked=="1" then 
     hwnd  = reaper.BR_Win32_GetMainHwnd()
     _,  hwnd_x,  hwnd_y = reaper.BR_Win32_GetWindowRect(hwnd)
  end
     
  laneID = -1 -- lane = -1 is the notes area
  tME_Lanes[-1] = {Type = -1, inlineHeight = 100} -- inlineHeight is not accurate, but will simply be used to indicate that this "lane" is large enough to be visible.
  for vellaneStr in activeTakeChunk:gmatch("\nVELLANE [^\n]+") do 
        laneType, ME_Height, inlineHeight = vellaneStr:match("VELLANE (%S+) (%d+) (%d+)")
        laneType, ME_Height, inlineHeight = ConvertCCTypeChunkToAPI(tonumber(laneType)), tonumber(ME_Height), tonumber(inlineHeight)
        if not (laneType and ME_Height and inlineHeight) then
            reaper.MB("Could not parse the VELLANE fields in the item state chunk.", "ERROR", 0)
            return(false)
        end    
        laneID = laneID + 1   
        tME_Lanes[laneID] = {VELLANE = vellaneStr, Type = laneType, ME_Height = ME_Height, inlineHeight = inlineHeight}
   end  
   
   if midiview then
        clientOK, rectLeft, rectTop, rectRight, rectBottom = reaper.JS_Window_GetClientRect(midiview) --takeChunk:match("CFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) (%S+) (%S+) (%S+)") 
           if not clientOK then 
               reaper.MB("Could not determine the MIDI editor's client window pixel coordinates.", "ERROR", 0) 
               return(false) 
           end 
       ME_midiviewWidth  = ((rectRight-rectLeft) >= 0) and (rectRight-rectLeft) or (rectLeft-rectRight)--ME_midiviewRightPixel - ME_midiviewLeftPixel + 1
       ME_midiviewHeight = ((rectTop-rectBottom) >= 0) and (rectTop-rectBottom) or (rectBottom-rectTop)--ME_midiviewBottomPixel - ME_midiviewTopPixel + 1
       local laneBottomPixel = ME_midiviewHeight-1
       for i = #tME_Lanes, 0, -1 do
           tME_Lanes[i].ME_BottomPixel = laneBottomPixel
           tME_Lanes[i].ME_TopPixel    = laneBottomPixel - tME_Lanes[i].ME_Height + 10
           laneBottomPixel = laneBottomPixel - tME_Lanes[i].ME_Height
       end
       tME_Lanes[-1].ME_BottomPixel = laneBottomPixel
       tME_Lanes[-1].ME_TopPixel    = 62
       tME_Lanes[-1].ME_Height      = laneBottomPixel-61
       ME_BottomPitch = topvisiblepitch - math.floor(tME_Lanes[-1].ME_Height / ME_PixelsPerPitch) 
   end 
end 



function draw(x,y,ch) 
    dcc = dcc +1 -- maybe do the delete here
    y = y +62 
    bitmaps[dcc] = reaper.JS_LICE_CreateBitmap(true, 20 ,20 ) 
    
    reaper.JS_LICE_DrawText( bitmaps[dcc], LICEFont, ch+1, 10,  0 , 0, 20, 20 )
    FontPos = ME_PixelsPerPitch/4  
    FontPos = math.floor(FontPos)
    did_it_work = reaper.JS_Composite(midiview  , x+2, y+FontPos, Fontsize , Fontsize ,  bitmaps[dcc], 0 , 0, 20 , 20 ,  false) 
   
end


function drawchnumber()  
    dcc = 0
    gotAllOK, MIDIstring = reaper.MIDI_GetAllEvts(take, "") 
    MIDIlen = MIDIstring:len()
    stringPos = 1  
    pos=0 
    while (stringPos < MIDIlen) do
      offset, flags, ms, stringPos = string.unpack("i4Bs4", MIDIstring, stringPos) 
      pos=pos+ offset 
      if ms:len() == 3 and ms:byte(1)>>4 == 9 then  
        if pos>= ME_LeftmostTick then 
          pitch = ms:byte(2) 
          if pitch<=topvisiblepitch and pitch>=ME_BottomPitch then
              factor = topvisiblepitch - pitch  
              pixelpos_y = ME_PixelsPerPitch*factor  
              factor = pos - ME_LeftmostTick
              pixelpos_x = factor *ME_HorzZoom  
              if tbase == 2 or tbase == 1 then 
                  timepos = reaper.MIDI_GetProjTimeFromPPQPos(take,  pos) 
                  ME_LeftmostTime    = reaper.MIDI_GetProjTimeFromPPQPos(take, ME_LeftmostTick)
                  factor = timepos -  ME_LeftmostTime 
                  pixelpos_x = factor *ME_HorzZoom  
               end  
              if ME_midiviewWidth -10 < factor *ME_HorzZoom then 
                 return 
              end 
              channel = ms:byte(1)&0x0F          
              draw (math.floor(pixelpos_x),math.floor(pixelpos_y),channel )
          end 
       end 
     end 
   end 
end  

reaper.atexit( function() 
    deleteChnumber() 
    local bs = reaper.SetToggleCommandState(sectionID ,({reaper.get_action_context()})[4],0) 
end) 

function deleteChnumber() 
          for j = 1 , #bitmaps do 
               reaper.JS_Composite_Unlink(midilink_F,bitmaps[j],false) 
               reaper.JS_LICE_DestroyBitmap(bitmaps[j])
          end 
end 


 

function main() 
    --mousex,mousey = reaper.GetMousePosition()
    update =false 
    hwnd = reaper.MIDIEditor_GetActive() 
    if hwnd then 
      take_=take 
      take = reaper.MIDIEditor_GetTake(hwnd) 
      if take~=take_ then update=true end 
      hash_ = hash or ""
      ret, hash = reaper.MIDI_GetHash(take,false,hash_)  
      if hash~=hash_ then update=true end 

    else return reaper.defer(main) end
    HORZ = {reaper.JS_Window_GetScrollInfo(midiview, "HORZ") } 
    VERT = {reaper.JS_Window_GetScrollInfo(midiview,"VERT")} 
    
    V_zoom_ = V_zoom or 0
    V_zoom = VERT[3] 
    V_scroll_ = V_scroll or 0
    V_scroll = VERT[2] 

    H_zoom_ = H_zoom or 0
    H_zoom = HORZ[3] 
    H_zoom2_ = H_zoom2 or 0
    H_zoom2 = HORZ[5]
    H_scroll_ = H_scroll or 0
    H_scroll = HORZ[2] 

    if V_zoom~=V_zoom_ or V_scroll~=V_scroll_ then 
        update =true 
     end 

     if H_zoom~=H_zoom_ or H_scroll~=H_scroll_ or H_zoom2~=H_zoom2_ then 
        update =true 
     end 

     if update then 
        readfromchunk() 
        deleteChnumber()
        drawchnumber() 
        update=false
     end
    reaper.defer(main) 
end 

main()

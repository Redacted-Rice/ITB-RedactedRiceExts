function onPawnClassInitialized(BoardPawn, pawn)
	BoardPawn.GetPilot = function(self)
	
	end
end
modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
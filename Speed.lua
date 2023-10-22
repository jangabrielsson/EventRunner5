--%%name=EventRunner5
--%%type=com.fibaro.genericDevice
--%%debug=refresh:false

function QuickApp:onInit()
    setInterval(function() print("OK",os.date("%c")) end,60*60*1000)
end
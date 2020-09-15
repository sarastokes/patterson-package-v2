function SquareGrating(varargin)
    import stage.core.*;

    ip = inputParser();
    ip.CaseSensitive = false;
    addParameter(ip, 'preTime', 500, @isnumeric);
    addParameter(ip, 'waitTime', 1000, @isnumeric);
    addParameter(ip, 'stimTime', 2000, @isnumeric);
    addParameter(ip, 'tailTime', 500, @isnumeric);
    addParameter(ip, 'backgroundIntensity', 0.5, @isnumeric);
    addParameter(ip, 'contrast', 1, @isnumeric);
    addParameter(ip, 'temporalFrequency', 2);
    addParameter(ip, 'spatialFrequency', 2);
    addParameter(ip, 'directions', 0:60:300, @isnumeric);
    addParameter(ip, 'gratingClass', 'squarewave', @ischar);
    addParameter(ip, 'canvasSize', [680 480], @isnumeric);
    parse(ip, varargin{:});
    
    obj = ip.Results;
    
    window = Window(obj.canvasSize, false);
    canvas = Canvas(window, 'disableDwm', false);
    
    for i = 1:numel(obj.directions)
        obj.direction = obj.directions(i);
        p = createPresentation(obj); 
        p.play(canvas);
    end
end

function p = createPresentation(obj)
    
    p = stage.core.Presentation((obj.preTime + obj.waitTime + obj.stimTime + obj.tailTime) * 1e-3);
    p.setBackgroundColor(obj.backgroundIntensity);
   
    canvasSize = obj.canvasSize;
    obj.baseGrating = getGrating(obj);
    
    grate = stage.builtin.stimuli.Image(uint8(0 * obj.baseGrating));
    grate.position = canvasSize / 2;
    grate.size = ceil(sqrt(canvasSize(1)^2 + canvasSize(2)^2))*ones(1,2);
    grate.orientation = obj.direction;
    grate.setMinFunction(GL.NEAREST);
    grate.setMagFunction(GL.NEAREST);
    p.addStimulus(grate);
    
    grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
        @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.waitTime + obj.stimTime) * 1e-3);
    p.addController(grateVisible); 
    
    imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
        @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
    p.addController(imgController);
    
    function g = setDriftingGrating(obj, time)
        if time >= 0
            phase = obj.temporalFrequency * time * 2 * pi;
        else
            phase = 0;
        end

        g = cos(phase + obj.baseGrating);

        if strcmp(obj.gratingClass, 'squarewave')
            g = sign(g);
        end

        g = obj.contrast * g;
        g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
    end
end

function baseGrating = getGrating(obj)
    canvasSize = obj.canvasSize;
    sz = ceil(sqrt(canvasSize(1)^2 + canvasSize(2)^2));
    [x,y] = meshgrid(...
        linspace(-sz/2, sz/2, sz), ...
        linspace(-sz/2, sz/2, sz));

    x = x / min(canvasSize) * 2 * pi;
    y = y / min(canvasSize) * 2 * pi;

    img = (cos(0)*x + sin(0) * y) * obj.spatialFrequency;
    baseGrating = repmat(img(1, :), [1, 1, 3]);
end
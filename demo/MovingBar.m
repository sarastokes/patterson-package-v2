function MovingBar(varargin)
    import stage.core.*;

    ip = inputParser();
    ip.CaseSensitive = false;
    addParameter(ip, 'preTime', 500, @isnumeric);
    addParameter(ip, 'stimTime', 2000, @isnumeric);
    addParameter(ip, 'tailTime', 500, @isnumeric);
    addParameter(ip, 'backgroundIntensity', 0.5, @isnumeric);
    addParameter(ip, 'contrast', 1, @isnumeric);
    addParameter(ip, 'speeds', 500, @isnumeric);
    addParameter(ip, 'barSize', [50, 240], @isnumeric);
    addParameter(ip, 'directions', 0:60:300, @isnumeric);
    addParameter(ip, 'apertureDiameter', 500, @isnumeric);
    addParameter(ip, 'canvasSize', [680 480], @isnumeric);
    addParameter(ip, 'centerOffset', [0 0], @isnumeric);
    addParameter(ip, 'micronsPerPixel', 1.3, @isnumeric);
    parse(ip, varargin{:});
    
    obj = ip.Results;    
    
    window = Window(obj.canvasSize, false);
    canvas = Canvas(window, 'disableDwm', false);
    
    % Account for both mean and zero mean options
    if obj.backgroundIntensity > 0
        obj.barIntensity = obj.backgroundIntensity * obj.contrast + obj.backgroundIntensity;
    else
        obj.barIntensity = obj.contrast;
    end
    
    % Iterate through the directions
    if numel(obj.directions) > 1
        obj.speed = obj.speeds;
        for i = 1:numel(obj.directions)
            obj.direction = obj.directions(i);
            p = createPresentation(obj); 
            p.play(canvas);
        end
    end
    
    % Iterate through the speeds
    if numel(obj.speeds) > 1
        obj.direction = obj.directions;
        for i = 1:numel(obj.speeds)
            obj.speed = obj.speeds(i);
            p = createPresentation(obj);
            p.play(canvas);
        end
    end
end

function p = createPresentation(obj)

    p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
    p.setBackgroundColor(obj.backgroundIntensity);
    
    % Get sizes
    canvasSize = obj.canvasSize;
    apertureDiameterPix = um2pix(obj, obj.apertureDiameter);
    centerOffsetPix = um2pix(obj, obj.centerOffset);
    barSizePix = um2pix(obj, obj.barSize);
    speedPix = um2pix(obj, obj.speed);
    directionRads = deg2rad(obj.direction);
    
    p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); 
    p.setBackgroundColor(obj.backgroundIntensity);
    
    rect = stage.builtin.stimuli.Rectangle();
    rect.size = barSizePix;
    rect.position = canvasSize/2 + centerOffsetPix;
    rect.orientation = obj.direction;
    rect.color = obj.barIntensity;
    p.addStimulus(rect);
    
    barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
        @(state)state.time >= obj.preTime * 1e-3...
        && state.time < (obj.preTime + obj.stimTime) * 1e-3);
    p.addController(barVisible);
    
    barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
        @(state)getBarPosition(obj, state.time - obj.preTime*1e-3));
    p.addController(barPosition);
    
    if obj.apertureDiameter > 0
        aperture = stage.builtin.stimuli.Rectangle();
        aperture.position = canvasSize/2 + centerOffsetPix;
        aperture.color = obj.backgroundIntensity;
        aperture.size = 2 * max(obj.canvasSize) * ones(1, 2);
        mask = stage.core.Mask.createCircularAperture(...
            apertureDiameterPix / (2 * max(canvasSize)));
        aperture.setMask(mask);
        p.addStimulus(aperture);
    else
        apertureDiameterPix = max(canvasSize);
    end
    
    function p = getBarPosition(~, time)
        inc = time * speedPix - (apertureDiameterPix/2) - barSizePix(1)/2;
        p = [cos(directionRads) sin(directionRads)] ...
            .* (inc * ones(1,2)) + canvasSize/2 + centerOffsetPix;
    end   
end

function pix = um2pix(obj, microns)
    pix = round(microns / obj.micronsPerPixel);
end
function out = VonMises(varargin)
% VONMISES
%
% Description:
%   Dependency-free, simplified port of Justin Gardner's fitVonMises
%
% History:
%   17Sep2020 - SSP
% -------------------------------------------------------------------------
    ip = inputParser();
    ip.CaseSensitive = false;
    addParameter(ip, 'X', [], @isnumeric);  % degrees
    addParameter(ip, 'Y', [], @isnumeric);
    addParameter(ip, 'Mu', 0, @isnumeric);
    addParameter(ip, 'Kappa', 5, @isnumeric);
    addParameter(ip, 'Amp', 1, @isnumeric);
    addParameter(ip, 'Offset', 0, @isnumeric);
    addParameter(ip, 'WrapAt', 360, @isnumeric);
    addParameter(ip, 'HalfWidthHalfHeight', [], @isnumeric);
    addParameter(ip, 'DisplayType', 'off', @ischar);
    addParameter(ip, 'PlotFit', false, @islogical);
    parse(ip, varargin{:});

    X = ip.Results.X(:);
    Y = ip.Results.Y(:);
    
    mu = ip.Results.Mu;
    kappa = ip.Results.Kappa;
    amp = ip.Results.Amp;
    offset = ip.Results.Offset;
    wrapAt = ip.Results.WrapAt;
    
    displayType = ip.Results.DisplayType;
    plotFit = ip.Results.PlotFit;
    if plotFit
        axesHandle = axes('Parent', figure());
    else
        axesHandle = [];
    end
        
    X_rads = deg2rad(X);
    mu_rads = deg2rad(mu);
    
    initParams = [mu_rads, kappa, amp, offset];

    if isempty(Y)
        out = myVonMises(initParams, X, 360/wrapAt);
        return
    end
     
    % Fit with nelder-mead
    opt = optimset('MaxFunEvals', 6000, 'Display', displayType);
    optimParams = fminsearch(@vonMisesError,... 
        initParams, opt, Y, X_rads, 0, axesHandle);
    if plotFit
        title(axesHandle, sprintf('[%u, %.3f, %.3f, %.3f]',... 
            round(rad2deg(optimParams(1))), optimParams(2:end)));
    end
    
    out.optimParams = optimParams;
    out.mu_rads = optimParams(1);
    out.mu = rad2deg(optimParams(1)); 
    out.kappa = optimParams(2);
    out.amp = optimParams(3);
    out.offset = optimParams(4);
    out.hwhh = kappa2hwhh(optimParams(2));
    out.yFit = myVonMises(optimParams, X_rads);
    out.xSmooth = min(X):max(X);
    out.yFitSmooth = myVonMises(optimParams, deg2rad(out.xSmooth));
    out.x = X;
    out.y = Y;
    
    try
        % Fit again with levenberg-marquardt (to get jacobian)
        opt = optimset('Algorithm', 'levenberg-marquardt',... 
            'MaxFunEvals', Inf, 'Display', displayType);
        [~, ~, residual, ~, ~, ~, jacobian] = lsqnonlin(@vonMisesError,...
            optimParams, [], [], opt, Y, X_rads, 1, []);
    
        % Reduced chi squared is a factor that decreases the value of the
        % parameter variance estimates according to how many degrees of freedom
        reducedChiSquared = (residual(:)' * residual(:)) / ...
            (length(Y) - length(initParams));
        % Get the covariance matrix as the inverse of the hessian matrix
        covar = reducedChiSquared * inv(jacobian' * jacobian);
    
        % Save parameters in return structure
        out.covar = covar;
        out.residual = residual;
        out.squaredError = sum(residual .^ 2);
    catch
        warning('VONMISES: No optimization toolbox, skipping error metrics');
    end
    
end

function y = myVonMises(params, x, wrapScaleFactor)
    % MYVONMISES
    if nargin < 3
        wrapScaleFactor = 1;
    end
    
    mu_rads = params(1);
    kappa = params(2);
    amp = params(3);
    offset = params(4);
    
    if ~isequal(wrapScaleFactor, 1)
        hwhh = kappa2hwhh(kappa);
        kappa = hwhh2kappa(hwhh * wrapScaleFactor);
        x = x * wrapScaleFactor;
        mu_rads = mu_rads * wrapScaleFactor;
    end
    
    % Von Mises normalized to that amplitude is the difference between the
    % lowest and highest points.
    y = offset + (amp-offset) * (exp(kappa * cos(x - mu_rads)) - ...
        exp(-kappa))/(exp(kappa)-exp(-kappa));
end

function out = vonMisesError(params, y, x, returnResidual, axesHandle)
    % VONMISESERROR 
    if nargin < 4
        axesHandle = [];
    end

    yFit = myVonMises(params, x);
    
    residual = y(:) - yFit(:);
    squaredError = sum(residual.^2);
    
    if returnResidual
        out = residual;
    else
        out = squaredError;
    end
    
    if ~isempty(axesHandle)
        hold(axesHandle, 'off');
        plot(axesHandle, rad2deg(x), y, 'xk',...
            'LineWidth', 1, 'LineStyle', 'none');
        hold(axesHandle, 'on');
        plot(axesHandle, rad2deg(x), yFit, 'b', 'LineWidth', 1.5);
        title(axesHandle, sprintf('%s : %0.4f', num2str(params), squaredError));
        ylim(axesHandle, [0, 1]);
        drawnow;
    end
end


function hwhh = kappa2hwhh(kappa)
    % KAPPA2HWHH
    if isinf(kappa)
        hwhh = 0;
    else
        hwhh = rad2deg(acos(log(((exp(kappa) - exp(-kappa))/2) + exp(-kappa)) ./ kappa));
    end
end

function k = hwhh2kappa(hwhh)
    % HWHH2KAPPA
    for i = 1:numel(hwhh)
        if hwhh(i) == 0
            k(i) = Inf;   %#ok<AGROW>
        else
            % Get cos of the desired angle
            th = cos(deg2rad(hwhh(i)));
            % Solve the equation to find what kappa makes it so
            % that theta gives a value of 0.5 (init at kappa = 1)
            k(iWidth) = fzero(...
                @(k) ((exp(k*th) - exp(-k))/(exp(k)-exp(-k)) - 0.5), 1); %#ok<AGROW>
        end
    end                   
end
   
classdef LiebLinigerModel < iFluidCore
    % Class specifying model specific quantities.
    % Solves the Bethe-Boltzmann equation for GHD propagation via the
    % superclass, which implements the general methods. 
    %
    % The units used in this parameterization are as follows:
    % m         = 1/2
    % hbar      = 1
    % g_1d      = 1
    % Lg        = hbar^2/(m*g_1d) = 1 (unit of length)
    % Eg        = 0.5*m*g_1d^2/hbar^2 = 1 (unit of energy)
    % rapidity  = k, whereby p = hbar*k = rapid
    %  
    
properties (Access = protected)

    % Species of quasiparticle
    quasiSpecies= 'fermion'; 
    
end % end private properties
    
    
methods (Access = public)
        
    % Constructor
    function obj = LiebLinigerModel(x_grid, rapid_grid, rapid_w, couplings, Options)   
        % Set default parameters
        if nargin < 5
            Options = struct;
        end
        
        % Lieb-Liniger model has 1 species of quasi-particles
        Ntypes = 1;
   
        % Call superclass constructor
        obj = obj@iFluidCore(x_grid, rapid_grid, rapid_w, couplings, Ntypes, Options);
    end
    
    
    %% Implementation of abstract equations
    function ebare = getBareEnergy(obj, t, x, rapid, type)
        % First coupling is chemical potential
        ebare = rapid.^2 - obj.couplings{1,1}(t,x);
    end
    
    
    function pbare = getBareMomentum(obj, t, x, rapid, type)
        pbare = rapid;
    end
    
    
    function de = calcEnergyRapidDeriv(obj, t, x, rapid, type)
        de = 2*rapid;
    end

    
    function dp = calcMomentumRapidDeriv(obj, t, x, rapid, type)
        dp = repmat(1, length(rapid), 1);
    end
    
    
    function dT = calcScatteringRapidDeriv(obj, t, x, rapid1, rapid2, type1, type2)
        % Reshape input to ensure right dimensions
        rapid1  = reshape(rapid1, length(rapid1), 1); % rapid1 is 1st index
        rapid2  = reshape(rapid2, 1, length(rapid2)); % rapid2 is 2nd index
        type1   = reshape(type1, 1, 1, length(type1)); % type1 is 3rd index
        type2   = reshape(type2, 1, 1, 1, length(type2)); % type2 is 4th index
        
        dT      = -2*obj.couplings{1,2}(t,x)./( (rapid1-rapid2).^2 + obj.couplings{1,2}(t,x).^2 );
        
        dT(isnan(dT)) = 0; % removes any NaN
        
        dT      = iFluidTensor(dT); % Converts to iFluidTensor
    end
    
    
    function de = calcEnergyCouplingDeriv(obj, coupIdx, t, x, rapid, type)
        if coupIdx == 1
            de = repmat(-1, length(rapid), 1);
        else
            de = 0;
        end
    end

    
    function dp = calcMomentumCouplingDeriv(obj, coupIdx, t, x, rapid, type)
       dp = 0;
    end
    
    
    function dT = calcScatteringCouplingDeriv(obj, coupIdx, t, x, rapid1, rapid2, type1, type2)
        % Reshape input to ensure right dimensions
        rapid1  = reshape(rapid1, length(rapid1), 1); % rapid1 is 1st index
        rapid2  = reshape(rapid2, 1, length(rapid2)); % rapid2 is 2nd index
        type1   = reshape(type1, 1, 1, length(type1)); % type1 is 3rd index
        type2   = reshape(type2, 1, 1, 1, length(type2)); % type2 is 4th index
        
        if coupIdx == 2
            dT = 2*(rapid1-rapid2)./( (rapid1-rapid2).^2 + + obj.couplings{1,2}(t,x).^2 );
        else
            dT = 0;
        end
        
        dT(isnan(dT)) = 0; % removes any NaN
        dT = iFluidTensor(dT); % Converts to iFluidTensor
    end
    
    
    function mu0_fit = fitAtomnumber(obj, T, V_ext, Natoms, mu0_guess, setCouplingFlag)
        % Finds mu_0 for a given potential, V_ext, and temperature, T,
        % corresponding to a given atomnumber.
        % NOTE: V_ext is anonymous function with argument (t,x).
        
        if nargin < 6
            setCouplingFlag = false;
        end
        
        if isempty(V_ext)
            V_ext = obj.couplings{1};
        end
        
        % Fit mu0 to Natoms
        fitfunc     = @(mu0) abs( Natoms - calcNA(obj, mu0, T, V_ext) );
        options     = optimset('Display','iter');
        mu0_fit     = fminsearch(fitfunc, mu0_guess,options);
        
        if setCouplingFlag % adjust couplings to result
            couplings_new   = obj.getCouplings();
            couplings_new{1,1}= @(t,x) mu0_fit - V_ext(t,x);

            obj.setCouplings(couplings_new);
        end
        
        function Natoms_fit = calcNA(obj, mu0, T, V_ext)
            % Calculates number of atoms in stationary TBA state given by
            % specied paramters.
            couplings_fit   = obj.getCouplings();
            couplings_fit{1,1}= @(t,x) mu0 - V_ext(t,x);
            theta           = obj.calcThermalState(T, couplings_fit);
            density         = obj.calcCharges(theta, 0, 0);
            Natoms_fit      = trapz(permute(obj.x_grid, [5 2 3 4 1]), density);
        end % end nested function
    end


    function [v_eff, a_eff] = calcEffectiveVelocities(obj, theta, t, x, rapid, type)        
        % Overloads method, as acceleration from mu has much simpler
        % expression than the general one.
        de_dr   = obj.applyDressing(obj.calcEnergyRapidDeriv(t, x, rapid, type), theta, t);
        dp_dr   = obj.applyDressing(obj.calcMomentumRapidDeriv(t, x, rapid, type), theta, t);
        
        v_eff   = de_dr./dp_dr;
        
        if obj.homoEvol % if homogeneous couplings, acceleration = 0
            a_eff = iFluidTensor( zeros(size( v_eff )) );
            return
        end
        
        % Calculate acceleration from inhomogenous potential. Note dmudt
        % does not contribute as f = 0;
        a_eff_mu = 0;
        if ~isempty(obj.couplings{3,1})
            a_eff_mu = obj.couplings{3,1}(t,x);
            if size(a_eff_mu,1) == 1
                a_eff_mu = repmat(a_eff_mu, length(rapid), 1); 
            end
        end
        a_eff_mu = iFluidTensor(a_eff_mu);
        
        % Calculate acceleration from inhomogenous interaction
        a_eff_c = 0;
        if ~isempty(obj.couplings{2,2}) || ~isempty(obj.couplings{3,2})
            % Calculate derivative of scattering phase with respect to
            % interaction c           
            dT      = obj.calcScatteringCouplingDeriv(2, t, x, rapid, obj.rapid_grid, type, obj.type_grid);
            B       = 1/(2*pi) * dT.*transpose(obj.rapid_w .* theta);
        end
        
        if ~isempty(obj.couplings{2,2}) % calc time deriv contribution
            f       = B*dp_dr;
            f_dr    = obj.applyDressing(f, theta, t);
            a_eff_c = a_eff_c + obj.couplings{2,2}(t,x).*f_dr;
        end

        if ~isempty(obj.couplings{3,2}) % calc space deriv contribution
            L       = B*de_dr;
            L_dr    = obj.applyDressing(L, theta, t);
            a_eff_c = a_eff_c + obj.couplings{3,2}(t,x).*L_dr;
        end
        
        a_eff_c = a_eff_c./dp_dr;
        a_eff   = a_eff_c + a_eff_mu;
    end
    
    
    function g_n = calcLocalCorrelator(obj, n, theta, t_array)
        Nsteps = length(t_array);
        g_n = zeros(obj.M, Nsteps);
        
        for k = 1:Nsteps
            if Nsteps == 1
                theta_k = theta;
                t       = t_array;
            else
                theta_k = theta{k};
                t       = t_array(k);
            end
            
            D       = obj.calcCharges(theta_k, 0, t); % density
            prefac  = factorial(n)^2 * (obj.couplings{1,2}(t,obj.x_grid)).^n / 2^n ./ D.^n;
        
            % Find integers m_j to sum over
            m_seq   = findMseq(1, zeros(1,n), n, []);
        
            % Calc B functions
            B = obj.calcB(n, theta_k, t);
            
            g_temp = 0;
            for i = 1:length(m_seq) % for each set {m_j}_i

                prod_temp = 1;
                for j = 1:n % for each member m_j in set
                    m_j     = m_seq{i}(j);

                    prod_temp = prod_temp .* ( 1/factorial(m_j) * (B{j}./(pi*obj.couplings{1,2}(t,obj.x_grid))).^m_j );
                end

                g_temp = g_temp + prod_temp;
            end
            
            g_n(:,k) = prefac.*squeeze(double(g_temp));
        end
        
        
        function m_seq = findMseq(j, m, n, m_seq)
            % Set first value to max possible
            R   = n - m*(1:n)';
            m(j) = ceil(R/j);

            while m(j) >= 0
                % Calculate remainder
                R_cur = n - m*(1:n)';

                if R_cur == 0
                    % save this configuration
                    m_seq{end+1} = m;
                elseif R_cur < 0
                    % no configurations possible
                else % remainder is positive
                    % look for more solutions later in sequence, but not further
                    % than the sequence length!
                    if j == n; return; end
                    m_seq = findMseq( j+1, m, n, m_seq);
                end

                m(j) = m(j) - 1;
            end
        end % end nested function
        
    end
    
        
    function B = calcB(obj, n, theta, t)
        b       = cell( 1 , 2*n - 1 + 2); % added two dummy indices
        b(:)    = {iFluidTensor( obj.N , 1 , 1 , 1 , obj.M )};
        
        kernel1 = -1/(2*pi)*obj.calcScatteringRapidDeriv(t, obj.x_grid, obj.rapid_grid, obj.rapid_grid, obj.type_grid, obj.type_grid);
        kernel2 = -(obj.rapid_grid - transpose(obj.rapid_grid)).*kernel1./obj.couplings{1,2}(t,obj.x_grid);
        
        X1      = eye(obj.N) - kernel1.*transpose(obj.rapid_w.*theta);
        
        for i = 1:(2*n - 1)                
            if mod(i,2) == 0 % i even
                X2      = -kernel1*(obj.rapid_w.*theta.*b{i-2+2}) + kernel2*(obj.rapid_w.*theta.*( 2*b{i-1+2} - b{i-3+2} ));
                b{i+2}  = X1\X2;
            else % i odd
                X2      = kernel2*(obj.rapid_w.*theta.*b{i-1+2}) - kernel1*(obj.rapid_w.*theta.*b{i-2+2});
                
                if i == 1 % delta function contribution for n = 0
                    X2 = X2 + 1;
                end
                
                b{i+2}  = X1\X2;
            end
        end
        
        B = cell(1, n);
        for i = 1:n
            B{i} = 1/i*transpose(theta)*(obj.rapid_w.*b{2*i - 1 + 2 });
        end
    end
    
      
end % end public methods

    
end % end classdef
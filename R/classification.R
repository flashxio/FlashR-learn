# Copyright 2016 Open Connectome Project (http://openconnecto.me)
# Written by Da Zheng (zhengda1936@gmail.com)
#
# This file is part of FlashR.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

logistic.grad <- function(X, y, w)
{
	gradient <- (t(X) %*% (1/(1 + exp(-X %*% t(w))) - y))
	return(t(gradient))
}

logistic.hessian <- function(X, y, w)
{
	exw <- exp(X %*% t(w))
	ifelse(is.infinite(exw), 0, exw/((1+exw)^2))
}

logistic.cost <- function(X, y, w)
{
	xw <- X %*% t(w)
	exw <- exp(xw)
	sum(y*(-xw) + ifelse(is.finite(exw), log(1 + exw), xw))
}

logistic.regression <- function(X, y, method=c("GD", "Newton", "LS", "RNS",
											   "Uniform", "LBFGS", "L-BFGS-B", "BFGS"),
								hessian_size=0.1, max.iters=500, standardize=TRUE)
{
	m <- if(is.vector(X)) length(X) else nrow(X)

	if (standardize) {
		X <- as.double(X)
		sum.x <- colSums(X)
		sum.x2 <- colSums(X * X)
		avg <- sum.x / m
		sd <- sqrt((sum.x2 - m * avg * avg) / (m - 1))
		center <- sum.x / m
		X <- fm.mapply.row(X, center, fm.bo.sub)
		# Multiply is much faster than division. X is a virtual matrix,
		# and this operation will be called many times.
		X <- fm.mapply.row(X, 1/sd, fm.bo.mul)
	}

	if(is.vector(X) || (!all(X[,1] == 1))) X <- cbind(fm.as.matrix(fm.rep.int(1, m)), X)
	# If the matrix is in row-major, we can avoid memory copy in matrix multiply.
	X <- fm.conv.layout(X, byrow=TRUE)
	X <- fm.materialize(X)

	if (method == "Newton" || method == "LS"
		|| method == "RNS" || method == "Uniform")
		get.hessian <- logistic.hessian
	else
		get.hessian <- NULL
	params <- list(c=0.5, ro=0.2, linesearch=is.null(get.hessian),
				   num.iters=max.iters, out.path=FALSE, method=method,
				   hessian_size=hessian_size, L=ncol(X))

	if (method == "L-BFGS-B" || method == "BFGS") {
		W <- NULL
		C <- NULL
		G <- NULL
		comp.cost_grad <- function(w) {
			xw <- X %*% w
			exw <- exp(xw)
			c <- sum(y*(-xw) + log(1 + exw))
			g <- (t(X) %*% (1/(1 + 1/exw) - y))
			c <- as.vector(c)/length(y)
			g <- as.vector(g)/length(y)
			W <<- w
			C <<- c
			G <<- g
		}
		cost <- function(w) {
			if (is.null(W) || any(W != w))
				comp.cost_grad(w)
			C
		}
		grad <- function(w) {
			if (is.null(W) || any(W != w))
				comp.cost_grad(w)
			G
		}
		# It seems lbfgs package can optimize the problem better.
		if (method == "L-BFGS-B") {
			res <- lbfgs::lbfgs(cost, grad, rep(0, ncol(X)), max_iterations = max.iters)
			res$par
		}
		else {
			res = optim(rep(0, ncol(X)), cost, gr=grad, method=method,
						control = list(trace=1, maxit=max.iters))
			res$value
		}
	}
	else
		gradient.descent(X, y, logistic.grad, get.hessian, cost=logistic.cost, params)
}

hinge.grad <- function(X, y, w)
{
	# y is {0, 1}. But y in the hinge loss requires y to be {-1, 1}.
	y <- 2 * y - 1

	xw <- X %*% t(w)
	zero <- fm.matrix(0, nrow(X), ncol(X))
	test <- fm.matrix(y * xw < 1.0, nrow(X), ncol(X))
	t(colSums(ifelse(test, -y * X, zero)))
}

hinge.loss <- function(X, y, w)
{
	# y is {0, 1}. But y in the hinge loss requires y to be {-1, 1}.
	y <- 2 * y - 1

	xw <- X %*% t(w)
	sum(ifelse(y * xw < 1.0, 1 - y * xw, 0))
}

SVM <- function(X, y, max.iters=500)
{
	params <- list(c=0.5, ro=0.2, linesearch=FALSE,
				   num.iters=max.iters, out.path=FALSE, method="GD")
	gradient.descent(X, y, hinge.grad, NULL, cost=hinge.loss, params)
}

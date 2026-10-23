import { StrictMode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { QueryClient } from "@tanstack/react-query";
import { act, create, type ReactTestRenderer } from "react-test-renderer";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  FIRST_MODEL_COMMAND,
  IntroScreen,
  default as Onboarding,
  RunOllamaScreen,
  WelcomeScreen,
} from "./Onboarding";
import { authenticationTimeoutAction } from "@/lib/onboarding";

let queryClient: QueryClient;
beforeEach(() => {
  queryClient = new QueryClient();
});
afterEach(() => queryClient.clear());

vi.mock("@tanstack/react-query", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@tanstack/react-query")>();
  return Object.assign({}, actual, {
    useQueryClient: () => queryClient,
    useMutation: (options: Parameters<typeof actual.useMutation>[0]) =>
      actual.useMutation(options, queryClient),
    useMutationState: (
      options: Parameters<typeof actual.useMutationState>[0],
    ) => actual.useMutationState(options, queryClient),
  });
});

describe("Onboarding", () => {
  it("explains what Ollama is before asking the user to choose a path", () => {
    const html = renderToStaticMarkup(<IntroScreen onContinue={vi.fn()} />);

    expect(html).toContain("Welcome to Ollama!");
    expect(html.indexOf('alt="Ollama waving"')).toBeLessThan(
      html.indexOf("Welcome to Ollama!"),
    );
    expect(html).toMatch(/<main class="light-only [^"]*bg-white/);
    expect(html).not.toMatch(/alt="Ollama waving" class="[^"]*dark:/);
    expect(html).toContain(
      "Run open models with your coding agents so you can spend less while keeping your data private.",
    );
    expect(html.indexOf("Connect your apps")).toBeLessThan(
      html.indexOf("Easily switch models"),
    );
    expect(html.indexOf("Easily switch models")).toBeLessThan(
      html.indexOf("Your data stays yours"),
    );
    expect(html).toContain("Power your existing coding apps with open models");
    expect(html).toContain("Swap between frontier models in one click.");
    expect(html).toContain("Your prompt data is never logged or trained on.");
    expect(html).toContain("Continue");
    expect(html).not.toContain("Skip");
  });

  it("renders without browser platform globals", () => {
    vi.stubGlobal("navigator", undefined);
    try {
      expect(() =>
        renderToStaticMarkup(<IntroScreen onContinue={vi.fn()} />),
      ).not.toThrow();
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("lets an in-flight authentication check finish before timing out", () => {
    expect(authenticationTimeoutAction(false, true)).toBe("defer");
    expect(authenticationTimeoutAction(false, false)).toBe("fail");
    expect(authenticationTimeoutAction(true, true)).toBe("ignore");
  });

  it("preserves the intro for a device that is already connected", () => {
    const html = renderToStaticMarkup(
      <Onboarding
        isAuthenticated
        isSigningIn={false}
        signInError={null}
        completionError={null}
        onFinish={vi.fn().mockResolvedValue(true)}
        onSignIn={vi.fn()}
        onSignUp={vi.fn()}
        onRetryCompletion={vi.fn()}
        onUseLocal={vi.fn()}
      />,
    );

    expect(html).toContain("Welcome to Ollama");
    expect(html).not.toContain("Run Ollama");
    expect(html).not.toContain("Sign up");
  });

  it("offers cloud sign-up, local setup, and sign in on the welcome screen", () => {
    const html = renderToStaticMarkup(
      <WelcomeScreen
        isAuthenticated={false}
        isSigningIn={false}
        signInError={null}
        onSignIn={vi.fn()}
        onSignUp={vi.fn()}
        onLocal={vi.fn()}
      />,
    );

    expect(html).toContain("Create an account");
    expect(html).toMatch(/<main class="light-only [^"]*bg-white/);
    expect(html).toContain(
      "Create your account for access to faster, larger open models.",
    );
    expect(html).toContain("Your data is never logged or trained on.");
    expect(html).toContain("Sign up");
    expect(html).toContain("No thanks, I&#x27;ll use Ollama locally");
    expect(html).toContain("Sign in");
    expect(html).not.toContain("Skip");
  });

  it("shows the cloud choice without a sign-in link for authenticated users", () => {
    const html = renderToStaticMarkup(
      <WelcomeScreen
        isAuthenticated
        isSigningIn={false}
        signInError={null}
        onSignIn={vi.fn()}
        onSignUp={vi.fn()}
        onLocal={vi.fn()}
      />,
    );

    expect(html).toContain("Create an account");
    expect(html).toContain(
      "Create your account for access to faster, larger open models.",
    );
    expect(html).toContain("Your data is never logged or trained on.");
    expect(html).not.toContain(">Sign in<");
  });

  it("shows only the local command on the final page", () => {
    const html = renderToStaticMarkup(
      <RunOllamaScreen completionError={null} onRetryCompletion={vi.fn()} />,
    );

    expect(html).toContain("Run Ollama");
    expect(html).toMatch(/<main class="light-only [^"]*bg-white/);
    expect(html).toContain(FIRST_MODEL_COMMAND);
    expect(html).not.toContain("Finish");
    expect(html).not.toContain("Sign in");
    expect(html).not.toContain("create an account");
  });

  it("shows the connecting state on the welcome action", () => {
    const html = renderToStaticMarkup(
      <WelcomeScreen
        isAuthenticated={false}
        isSigningIn
        signInError={null}
        onSignIn={vi.fn()}
        onSignUp={vi.fn()}
        onLocal={vi.fn()}
      />,
    );

    expect(html).toContain("Finish in your browser…");
    expect(html).not.toContain("Waiting for sign in…");
  });

  it("shows a retryable error when onboarding completion cannot be saved", () => {
    const html = renderToStaticMarkup(
      <RunOllamaScreen
        completionError="Unable to save setup. Please try again."
        onRetryCompletion={vi.fn()}
      />,
    );

    expect(html).toContain("Unable to save setup. Please try again.");
    expect(html).toContain('role="alert"');
    expect(html).toContain("Try again");
  });
});

function onboardingProps(onFinish: () => Promise<boolean>) {
  return {
    isAuthenticated: true,
    isSigningIn: false,
    signInError: null,
    completionError: null,
    onFinish,
    onSignIn: vi.fn(),
    onSignUp: vi.fn(),
    onRetryCompletion: vi.fn(),
    onUseLocal: vi.fn(),
  };
}

function stubOnboardingWindow(platform = "darwin") {
  vi.stubGlobal("window", {
    OLLAMA_PLATFORM: platform,
    setOnboardingWindow: vi.fn(),
  });
}

async function settle(ticks = 8) {
  for (let i = 0; i < ticks; i++) {
    await Promise.resolve();
  }
}

describe("Onboarding handoff", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("finishes setup once when an authenticated intro continues", async () => {
    stubOnboardingWindow();
    const onFinish = vi.fn().mockResolvedValue(true);
    const props = onboardingProps(onFinish);
    let renderer: ReactTestRenderer | undefined;
    try {
      await act(async () => {
        renderer = create(
          <StrictMode>
            <Onboarding {...props} />
          </StrictMode>,
        );
      });
      await act(async () => {
        renderer!.root.findByType(IntroScreen).props.onContinue();
      });
      await settle();
      expect(onFinish).toHaveBeenCalledOnce();
    } finally {
      if (renderer) act(() => renderer?.unmount());
    }
  });

  it("stays on the intro when finishing setup fails", async () => {
    stubOnboardingWindow();
    const onFinish = vi.fn().mockResolvedValue(false);
    const props = onboardingProps(onFinish);
    let renderer: ReactTestRenderer | undefined;
    try {
      await act(async () => {
        renderer = create(<Onboarding {...props} />);
      });
      await act(async () => {
        await renderer!.root.findByType(IntroScreen).props.onContinue();
      });
      await settle();
      expect(renderer!.root.findByType(IntroScreen)).toBeTruthy();
      expect(renderer!.root.findByType(IntroScreen).props.isLeaving).toBe(
        false,
      );
    } finally {
      if (renderer) act(() => renderer?.unmount());
    }
  });

  it("preserves local setup without leaving onboarding", async () => {
    stubOnboardingWindow();
    const props = { ...onboardingProps(vi.fn()), isAuthenticated: false };
    let renderer: ReactTestRenderer | undefined;
    try {
      await act(async () => {
        renderer = create(<Onboarding {...props} />);
      });
      await act(async () => {
        renderer!.root.findByType(IntroScreen).props.onContinue();
      });
      expect(props.onFinish).not.toHaveBeenCalled();
      await act(async () => {
        renderer!.root.findByType(WelcomeScreen).props.onLocal();
      });
      expect(renderer!.root.findByType(RunOllamaScreen)).toBeTruthy();
      expect(props.onUseLocal).toHaveBeenCalledOnce();
    } finally {
      if (renderer) act(() => renderer?.unmount());
    }
  });
});

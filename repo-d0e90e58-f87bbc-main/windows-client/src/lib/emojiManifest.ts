// ════════════════════════════════════════════════════════════════════
// Plink Emoji Manifest — 5 packs, 81 emojis (PNG + GIF)
// ════════════════════════════════════════════════════════════════════
// Source: plink_emoji_packs.zip (user-provided)
// All packs are PREMIUM (Plink+ only).
// Free tier: 8 standard unicode emojis (👍❤️🔥😂😮😢🎉💯).
// ════════════════════════════════════════════════════════════════════

export interface EmojiItem {
  id: string;
  name: string;
  src: string; // /emoji-packs/{pack}/{file}
  animated: boolean; // true for .gif
}

export interface EmojiPack {
  id: string;
  name: string;
  premium: boolean;
  icon: string; // preview emoji src
  emojis: EmojiItem[];
}

const P = '/emoji-packs';

export const EMOJI_PACKS: EmojiPack[] = [
  // ═══════════════════════════════════════════════════════════════
  // 1. CUTE FACES (28 emojis)
  // ═══════════════════════════════════════════════════════════════
  {
    id: 'cute-faces',
    name: 'Cute Faces',
    premium: true,
    icon: `${P}/cute-faces/1403-owo.png`,
    emojis: [
      { id: 'owo', name: 'OwO', src: `${P}/cute-faces/1403-owo.png`, animated: false },
      { id: 'oh', name: 'Oh', src: `${P}/cute-faces/34080-oh.png`, animated: false },
      { id: 'shy', name: 'Shy', src: `${P}/cute-faces/34904-shy.png`, animated: false },
      { id: 'sup', name: 'Sup Shawty', src: `${P}/cute-faces/4208-sup-shawty.png`, animated: false },
      { id: 'embarrassed', name: 'Embarrassed', src: `${P}/cute-faces/4496-embarassed.png`, animated: false },
      { id: 'staring', name: 'Staring', src: `${P}/cute-faces/45654-staring.png`, animated: false },
      { id: 'munching', name: 'Munching', src: `${P}/cute-faces/5181-munching.png`, animated: false },
      { id: 'pat-pat', name: 'Pat Pat', src: `${P}/cute-faces/57751-pat-pat-give.png`, animated: false },
      { id: 'confused', name: 'Confused', src: `${P}/cute-faces/6687-emoji-confused.png`, animated: false },
      { id: 'sleepy', name: 'Sleepy', src: `${P}/cute-faces/6912-emoji-sleepy.png`, animated: false },
      { id: 'blehhh', name: 'Blehhh', src: `${P}/cute-faces/8036-blehhh.png`, animated: false },
      { id: 'owono', name: 'OwOno', src: `${P}/cute-faces/8237-owono.png`, animated: false },
      { id: 'murder', name: 'Murder', src: `${P}/cute-faces/8468-emoji-murder.png`, animated: false },
      { id: 'petpet', name: 'PetPet', src: `${P}/cute-faces/8596-petpetemoji.png`, animated: false },
      { id: 'birthday', name: 'Birthday', src: `${P}/cute-faces/9288-emoji-birthdayhat.png`, animated: false },
      { id: 'zooted', name: 'Zooted', src: `${P}/cute-faces/93422-zooted.png`, animated: false },
      { id: 'aww', name: 'Aww', src: `${P}/cute-faces/9732-awwemojix.png`, animated: false },
      { id: 'inlove-hearts', name: 'In Love', src: `${P}/cute-faces/9848-inlovehearts.png`, animated: false },
      { id: 'knife', name: 'Knife', src: `${P}/cute-faces/1217-emoji-knife.png`, animated: false },
      { id: 'loading', name: 'Loading', src: `${P}/cute-faces/22981-loading.png`, animated: false },
      { id: 'rainboarf', name: 'Rainbow', src: `${P}/cute-faces/2695-rainboarf.png`, animated: false },
      { id: 'cursed', name: 'Cursed', src: `${P}/cute-faces/3090-cursedemojieepy.png`, animated: false },
      { id: 'sighh', name: 'Sighh', src: `${P}/cute-faces/3123-sighh.png`, animated: false },
      { id: 'pleadcat', name: 'Plead Cat', src: `${P}/cute-faces/3380-emoji-pleadcat.png`, animated: false },
      { id: 'cute-cat', name: 'Cat', src: `${P}/cute-faces/10870-cuteemojiwithcat.png`, animated: false },
      { id: 'explain', name: 'Explain', src: `${P}/cute-faces/4990-explainthisshit.png`, animated: false },
      { id: '12', name: '12', src: `${P}/cute-faces/10221-12.png`, animated: false },
      { id: 'rainbow-gif', name: 'Rainbow', src: `${P}/cute-faces/8714-take-my-loverainbow.gif`, animated: true },
    ],
  },

  // ═══════════════════════════════════════════════════════════════
  // 2. PEPE (24 emojis — 14 PNG + 10 GIF)
  // ═══════════════════════════════════════════════════════════════
  {
    id: 'pepe',
    name: 'Pepe',
    premium: true,
    icon: `${P}/pepe/830563-pepe.png`,
    emojis: [
      { id: 'pepe', name: 'Pepe', src: `${P}/pepe/830563-pepe.png`, animated: false },
      { id: 'pepesmile', name: 'Smile', src: `${P}/pepe/383141-pepesmile.png`, animated: false },
      { id: 'pepeheart', name: 'Heart', src: `${P}/pepe/149743-pepeheart.png`, animated: false },
      { id: 'pepecross', name: 'Cross', src: `${P}/pepe/120458-pepecross.png`, animated: false },
      { id: 'pepeperfect', name: 'Perfect', src: `${P}/pepe/182109-pepeperfect.png`, animated: false },
      { id: 'pepedumb', name: 'Dumb', src: `${P}/pepe/236705-pepedumb.png`, animated: false },
      { id: 'pepehang', name: 'Hang', src: `${P}/pepe/304977-pepehang.png`, animated: false },
      { id: 'pepescream', name: 'Scream', src: `${P}/pepe/543336-pepescream.png`, animated: false },
      { id: 'pepeooo', name: 'OOO', src: `${P}/pepe/583748-pepeooo.png`, animated: false },
      { id: 'pepeokay', name: 'Okay', src: `${P}/pepe/618704-pepeokay.png`, animated: false },
      { id: 'kingpepe-1', name: 'King', src: `${P}/pepe/702336-kingpepe.png`, animated: false },
      { id: 'kingpepe-2', name: 'King 2', src: `${P}/pepe/733150-kingpepe.png`, animated: false },
      { id: 'nou', name: 'NO U', src: `${P}/pepe/798781-nou.png`, animated: false },
      { id: 'praypepe', name: 'Pray', src: `${P}/pepe/877975-praypepe.png`, animated: false },
      // GIF animated
      { id: 'pepetyping', name: 'Typing', src: `${P}/pepe/121023-pepetyping.gif`, animated: true },
      { id: 'pepelaugh', name: 'Laugh', src: `${P}/pepe/175472-pepelaugh.gif`, animated: true },
      { id: 'strongpepe', name: 'Strong', src: `${P}/pepe/249299-strongpepe.gif`, animated: true },
      { id: 'pepeclap', name: 'Clap', src: `${P}/pepe/431882-pepeclap.gif`, animated: true },
      { id: 'pepetorch', name: 'Torch', src: `${P}/pepe/436131-pepetorchfire.gif`, animated: true },
      { id: 'pepeuwu', name: 'UwU', src: `${P}/pepe/588971-pepeuwu.gif`, animated: true },
      { id: 'pepelmao', name: 'LMAO', src: `${P}/pepe/690612-pepelmao.gif`, animated: true },
      { id: 'peperain', name: 'Rain', src: `${P}/pepe/827729-peperain.gif`, animated: true },
      { id: 'peperich', name: 'Rich', src: `${P}/pepe/828203-peperich.gif`, animated: true },
      { id: 'pepehacker', name: 'Hacker', src: `${P}/pepe/950522-pepehacker.gif`, animated: true },
    ],
  },

  // ═══════════════════════════════════════════════════════════════
  // 3. EMOJIS (16 stickers)
  // ═══════════════════════════════════════════════════════════════
  {
    id: 'emojis',
    name: 'Stickers',
    premium: true,
    icon: `${P}/emojis/18038-wassup.png`,
    emojis: [
      { id: 'wassup', name: 'Wassup', src: `${P}/emojis/18038-wassup.png`, animated: false },
      { id: 'stinky', name: 'Stinky', src: `${P}/emojis/233828-stinky.png`, animated: false },
      { id: 'redcard', name: 'Red Card', src: `${P}/emojis/440174-redcard.png`, animated: false },
      { id: 'inlove', name: 'In Love', src: `${P}/emojis/455353-inlove.png`, animated: false },
      { id: 'plotting', name: 'Plotting', src: `${P}/emojis/486800-plotting.png`, animated: false },
      { id: 'nobrain', name: 'No Brain', src: `${P}/emojis/501481-nobrain.png`, animated: false },
      { id: 'downvote', name: 'Downvote', src: `${P}/emojis/502259-downvote.png`, animated: false },
      { id: 'licking', name: 'Licking Screen', src: `${P}/emojis/549205-lickingscreen.png`, animated: false },
      { id: 'approve', name: 'Approve', src: `${P}/emojis/559934-approve.png`, animated: false },
      { id: 'glasses', name: 'Glasses', src: `${P}/emojis/600559-glasses.png`, animated: false },
      { id: 'peace', name: 'Peace', src: `${P}/emojis/617091-peace.png`, animated: false },
      { id: 'hungry', name: 'Hungry', src: `${P}/emojis/67803-hungry.png`, animated: false },
      { id: 'give', name: 'Give', src: `${P}/emojis/767943-give.png`, animated: false },
      { id: 'gunpoint', name: 'Gunpoint', src: `${P}/emojis/77254-gunpoint.png`, animated: false },
      { id: 'fight', name: 'Fight', src: `${P}/emojis/794547-fight.png`, animated: false },
      { id: 'moneyhands', name: 'Money', src: `${P}/emojis/980819-moneyhands.png`, animated: false },
    ],
  },

  // ═══════════════════════════════════════════════════════════════
  // 4. CAT (6 emojis)
  // ═══════════════════════════════════════════════════════════════
  {
    id: 'cat',
    name: 'Cats',
    premium: true,
    icon: `${P}/cat/129403-flowersforyou.png`,
    emojis: [
      { id: 'flowers', name: 'Flowers', src: `${P}/cat/129403-flowersforyou.png`, animated: false },
      { id: 'cat-stinky', name: 'Stinky', src: `${P}/cat/233828-stinky.png`, animated: false },
      { id: 'cat-plotting', name: 'Plotting', src: `${P}/cat/486800-plotting.png`, animated: false },
      { id: 'sadqueen', name: 'Sad Queen', src: `${P}/cat/563716-sadqueen.png`, animated: false },
      { id: 'cat-peace', name: 'Peace', src: `${P}/cat/617091-peace.png`, animated: false },
      { id: 'ring', name: 'Ring', src: `${P}/cat/736199-ring.png`, animated: false },
    ],
  },

  // ═══════════════════════════════════════════════════════════════
  // 5. ZE FROG ES LE PEPE (7 emojis — 6 PNG + 1 GIF)
  // ═══════════════════════════════════════════════════════════════
  {
    id: 'ze-frog-es-le-pepe',
    name: 'Le Pepe',
    premium: true,
    icon: `${P}/ze-frog-es-le-pepe/857990-pepohappy.png`,
    emojis: [
      { id: 'blushy', name: 'Blushy', src: `${P}/ze-frog-es-le-pepe/3439-pepe-blushy.png`, animated: false },
      { id: 'pepe-sad', name: 'Sad', src: `${P}/ze-frog-es-le-pepe/370700-pepe-sad.png`, animated: false },
      { id: 'pepehug', name: 'Hug', src: `${P}/ze-frog-es-le-pepe/477732-pepehug.png`, animated: false },
      { id: 'pepes-le', name: 'Pepes', src: `${P}/ze-frog-es-le-pepe/638973-pepes.png`, animated: false },
      { id: 'sleepypepe', name: 'Sleepy', src: `${P}/ze-frog-es-le-pepe/733056-sleepypepe.png`, animated: false },
      { id: 'pepohappy', name: 'Happy', src: `${P}/ze-frog-es-le-pepe/857990-pepohappy.png`, animated: false },
      { id: 'pepe-hehe', name: 'Hehe', src: `${P}/ze-frog-es-le-pepe/47945-pepe-hehe.gif`, animated: true },
    ],
  },
];

// ════════════════════════════════════════════════════════════════════
// FREE emojis (8 standard unicode — доступны всем пользователям)
// ════════════════════════════════════════════════════════════════════
export const FREE_EMOJIS: EmojiItem[] = [
  { id: '👍', name: 'Thumbs Up', src: '', animated: false },
  { id: '❤️', name: 'Heart', src: '', animated: false },
  { id: '🔥', name: 'Fire', src: '', animated: false },
  { id: '😂', name: 'Joy', src: '', animated: false },
  { id: '😮', name: 'Wow', src: '', animated: false },
  { id: '😢', name: 'Sad', src: '', animated: false },
  { id: '🎉', name: 'Party', src: '', animated: false },
  { id: '💯', name: '100', src: '', animated: false },
];

// ════════════════════════════════════════════════════════════════════
// Helper — найти emoji по id (для рендера в chat bubble)
// ════════════════════════════════════════════════════════════════════
export function findEmojiById(id: string): EmojiItem | null {
  for (const pack of EMOJI_PACKS) {
    const found = pack.emojis.find((e) => e.id === id);
    if (found) return found;
  }
  return null;
}

// ════════════════════════════════════════════════════════════════════
// Helper — все packs + free, для picker tabs
// ════════════════════════════════════════════════════════════════════
export const ALL_PACKS: (EmojiPack & { isFree?: boolean })[] = [
  {
    id: 'free',
    name: 'Standard',
    premium: false,
    isFree: true,
    icon: '',
    emojis: FREE_EMOJIS,
  },
  ...EMOJI_PACKS,
];

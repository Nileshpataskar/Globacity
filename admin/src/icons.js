/* One Lucide icon per dashboard area (sidebar, page headers, empty states). */
import {
  AlertTriangle, BadgeCheck, Building2, CalendarCheck, CalendarDays, CircleDollarSign, DoorOpen, FileText,
  Fence, Hammer, HeartPulse, LayoutDashboard, Landmark, Map, Megaphone, MessagesSquare, ReceiptText,
  ShieldAlert, Siren, Settings, Tags, Truck, UserCog, Users, Vote, Wallet, Wrench, Footprints, ShoppingBag, Bookmark,
  ShieldCheck, Clock,
} from 'lucide-react';

export const ICONS = {
  overview: LayoutDashboard,
  residents: Users,
  towers: Building2,
  units: DoorOpen,
  gates: Fence,
  settings: Settings,
  'bulk-bill': ReceiptText,
  invoices: FileText,
  payments: Wallet,
  defaulters: AlertTriangle,
  'charge-types': Tags,
  tickets: Wrench,
  'ticket-categories': Bookmark,
  notices: Megaphone,
  polls: Vote,
  events: CalendarDays,
  'move-requests': Truck,
  vendors: Hammer,
  bookings: CalendarCheck,
  'visitor-log': Footprints,
  'guard-duty': ShieldCheck,
  'guard-shifts': Clock,
  sos: Siren,
  incidents: ShieldAlert,
  forum: MessagesSquare,
  classifieds: ShoppingBag,
  staff: UserCog,
  'emergency-contacts': HeartPulse,
  'platform-communities': Landmark,
  'platform-cities': Map,
  money: CircleDollarSign,
  approve: BadgeCheck,
};

export const iconFor = (key) => ICONS[key] || LayoutDashboard;
